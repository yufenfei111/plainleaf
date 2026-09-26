import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'entries_dao.g.dart';

/// 时间轴行：entries + 首图 + 笔记本，一条时间轴卡片所需数据一次拉齐
class TimelineRow {
  final Entry entry;
  final Asset? firstAsset;
  final Notebook? notebook;

  const TimelineRow({required this.entry, this.firstAsset, this.notebook});
}

/// 日历/回忆用的一条轻量命中：只有主键与日期
///
/// 为什么不直接给 Entry：日历一次要看一整月，带正文的行读出来是纯浪费，
/// 真正需要展示内容时再由 [_$EntriesDaoMixin] 的 watchOnThisDay 补详情。
class EntryDateHit {
  final int id;
  final DateTime date;

  const EntryDateHit({required this.id, required this.date});
}

@DriftAccessor(tables: [Entries, Assets, Notebooks])
class EntriesDao extends DatabaseAccessor<PlainLeafDatabase>
    with _$EntriesDaoMixin {
  EntriesDao(super.db);

  /// 时间轴流：未删除、非草稿条目，置顶优先 + 日期倒序，流式联首图与笔记本
  ///
  /// W7 起支持筛选（notebookId / type / pinnedOnly）：
  /// 过滤一律下推到 SQL where，**不做客户端过滤**——否则先 LIMIT 100 再筛，
  /// 会出现"筛选后只剩几条"的假象（数据其实被截断在前面）。
  Stream<List<TimelineRow>> watchTimeline({
    int limit = 100,
    int? notebookId,
    String? type,
    bool pinnedOnly = false,
  }) {
    final query = select(entries)
      ..where((e) {
        var cond = e.deleted.equals(false) & e.status.equals('normal');
        if (notebookId != null) cond = cond & e.notebookId.equals(notebookId);
        if (type != null) cond = cond & e.type.equals(type);
        if (pinnedOnly) cond = cond & e.pinned.equals(true);
        return cond;
      })
      ..orderBy([
        (e) => OrderingTerm.desc(e.pinned),
        (e) => OrderingTerm.desc(e.entryDate),
      ])
      ..limit(limit);

    return query.watch().asyncMap(_rowsFor);
  }

  /// 组装时间轴行：一次把首图与笔记本查齐（N 次 tao dao → 3 次查询）
  ///
  /// 抽成单独方法是因为 W12 起有了第二个消费方（那年今日）：
  /// 与其把 map / 首图归并复制一遍，不如共用同一套组装逻辑。
  Future<List<TimelineRow>> _rowsFor(List<Entry> entryList) async {
    if (entryList.isEmpty) return const <TimelineRow>[];
    final ids = entryList.map((e) => e.id).toList();

    final assetRows = await (select(assets)
          ..where((a) =>
              a.entryId.isIn(ids) &
              a.deleted.equals(false) &
              a.kind.equals('image'))
          ..orderBy([(a) => OrderingTerm.asc(a.sortIndex)]))
        .get();
    final notebookRows = await select(notebooks).get();

    final firstAssetByEntry = <int, Asset>{};
    for (final a in assetRows) {
      final eid = a.entryId;
      if (eid != null) firstAssetByEntry.putIfAbsent(eid, () => a);
    }
    final notebookById = {for (final n in notebookRows) n.id: n};

    return [
      for (final e in entryList)
        TimelineRow(
          entry: e,
          firstAsset: firstAssetByEntry[e.id],
          notebook: e.notebookId == null ? null : notebookById[e.notebookId!],
        ),
    ];
  }

  /// 日历/回忆视图用的一行轻量数据：**只有 id 与日期**，不带正文
  ///
  /// 日历热力只需要「哪天有几条」，把整行拉出来会把 contentDelta 这种
  /// 大字段一起读进内存——一个月三十来条没事，日历一次看一整月就会放大。
  /// 上层按列表自己在 Dart 里聚合（分组是常数级开销，换来的是不需要 SQLite
  /// 日期函数：那些函数在不同版本可用性不一致，写错一个函数名要等运行时才炸）。
  Stream<List<EntryDateHit>> watchEntryDates(DateTime from, DateTime to) {
    final query = selectOnly(entries)
      ..addColumns([entries.id, entries.entryDate])
      ..where(
        entries.deleted.equals(false) &
            entries.status.equals('normal') &
            entries.entryDate.isBiggerOrEqualValue(from) &
            entries.entryDate.isSmallerThanValue(to),
      )
      ..orderBy([OrderingTerm.desc(entries.entryDate)]);

    return query.watch().map(
          (rows) => [
            for (final r in rows)
              EntryDateHit(
                id: r.read(entries.id)!,
                date: r.read(entries.entryDate)!,
              ),
          ],
        );
  }

  /// 那年今日：往年同月同日写下、且不是今天的记录（新 → 旧，最多 limit 条）
  ///
  /// 过滤放在 Dart 层：月日匹配如果用 SQLite 日期函数写，换 engine 就有
  /// 行为差异；个人库的量级里这一步是纳秒级，换确定性划算。
  Stream<List<TimelineRow>> watchOnThisDay(DateTime today, {int limit = 3}) {
    final from = DateTime(today.year - 20, 1, 1);
    final to = DateTime(today.year, 1, 1);
    return watchEntryDates(from, to).asyncMap((rows) async {
      final hits = rows
          .where((hit) =>
              hit.date.month == today.month &&
              hit.date.day == today.day &&
              hit.date.year != today.year)
          .take(limit)
          .map((hit) => hit.id)
          .toList();
      if (hits.isEmpty) return const <TimelineRow>[];
      final entryList = await (select(entries)
            ..where((e) => e.id.isIn(hits))
            ..orderBy([(e) => OrderingTerm.desc(e.entryDate)]))
          .get();
      return _rowsFor(entryList);
    });
  }

  // ── 生命周期：创建 / 更新（W3 记录内核，全部事务双写 FTS） ──────────

  /// 保存新记录（事务双写）：entries 插入 + entries_fts 全文索引，同一事务落库。
  /// —— §4.3 数据红线：双写走数据层事务（不用 trigger），保证可测试、可回滚。
  Future<int> saveEntry({
    required EntriesCompanion entry,
    required String ftsTitle,
    required String ftsContent,
  }) {
    return transaction(() async {
      final id = await into(entries).insert(entry);
      await _upsertFtsRow(id, ftsTitle, ftsContent);
      return id;
    });
  }

  /// 更新内容字段（事务双写）：entries 更新 + entries_fts 重写，同一事务。
  /// 仅允许触碰内容相关列；uuid/createdAt/version 由调用方语义控制。
  Future<void> updateEntryContent(
    int id, {
    required String title,
    required String plainText,
    required String contentDelta,
    required String ftsTitle,
    required String ftsContent,
  }) {
    return transaction(() async {
      final row =
          await (select(entries)..where((e) => e.id.equals(id))).getSingle();
      await (update(entries)..where((e) => e.id.equals(id))).write(
        EntriesCompanion(
          title: Value(title),
          plainText: Value(plainText),
          contentDelta: Value(contentDelta),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
      await _upsertFtsRow(id, ftsTitle, ftsContent);
    });
  }

  /// 软删除（事务双删）：entries.deleted 置位 + version 递增，同时清除 FTS 行。
  /// 数据红线：一律软删除，物理行保留（回收站 30 天清理 W7 接入）。
  Future<void> softDelete(int id) {
    return transaction(() async {
      final row =
          await (select(entries)..where((e) => e.id.equals(id))).getSingle();
      await (update(entries)..where((e) => e.id.equals(id))).write(
        EntriesCompanion(
          deleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
      await customStatement('DELETE FROM entries_fts WHERE entry_id = ?', [id]);
    });
  }

  /// 从回收站恢复：deleted 复位 + FTS 行重建，同一事务。
  Future<void> restore(int id) {
    return transaction(() async {
      final row =
          await (select(entries)..where((e) => e.id.equals(id))).getSingle();
      await (update(entries)..where((e) => e.id.equals(id))).write(
        EntriesCompanion(
          deleted: const Value(false),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
      await _upsertFtsRow(id, row.title, row.plainText);
    });
  }

  // ── 草稿箱 / 回收站查询（W3） ────────────────────────────────────

  /// 草稿箱流：未删除 + status=draft，按 updatedAt 倒序
  Stream<List<Entry>> watchDrafts() {
    return (select(entries)
          ..where((e) => e.deleted.equals(false) & e.status.equals('draft'))
          ..orderBy([(e) => OrderingTerm.desc(e.updatedAt)]))
        .watch();
  }

  /// 回收站流：已删除条目，按 updatedAt 倒序（30 天保留窗口展示）
  Stream<List<Entry>> watchTrash() {
    return (select(entries)
          ..where((e) => e.deleted.equals(true))
          ..orderBy([(e) => OrderingTerm.desc(e.updatedAt)]))
        .watch();
  }

  /// 单条记录（详情/编辑器载入用）
  Future<Entry?> findById(int id) =>
      (select(entries)..where((e) => e.id.equals(id))).getSingleOrNull();

  /// 修改状态（draft → normal 等）：version 递增
  Future<void> setStatus(int id, {required String status}) {
    return transaction(() async {
      final row =
          await (select(entries)..where((e) => e.id.equals(id))).getSingle();
      await (update(entries)..where((e) => e.id.equals(id))).write(
        EntriesCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }

  /// 更新分类元数据（W10 编辑器属性条）：类型 / 笔记本 / 心情。
  /// 只触碰这三列 + updatedAt/version，内容与 FTS 不受影响——
  /// 改分类不重写 FTS，是因为 FTS 只索引标题与正文，分类变化不改变检索结果。
  ///
  /// [notebookId]/[mood] 用 drift 的 `Value` 三态：
  /// absent（不动）/ Value(x)（设为 x）/ Value(null)（清空为 NULL）。
  Future<void> updateEntryMeta(
    int id, {
    String? type,
    Value<int?> notebookId = const Value.absent(),
    Value<int?> mood = const Value.absent(),
  }) {
    return transaction(() async {
      final row =
          await (select(entries)..where((e) => e.id.equals(id))).getSingle();
      await (update(entries)..where((e) => e.id.equals(id))).write(
        EntriesCompanion(
          type: type == null ? const Value.absent() : Value(type),
          notebookId: notebookId,
          mood: mood,
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }

  /// 置顶开关：version 递增
  Future<void> setPinned(int id, {required bool pinned}) {
    return transaction(() async {
      final row =
          await (select(entries)..where((e) => e.id.equals(id))).getSingle();
      await (update(entries)..where((e) => e.id.equals(id))).write(
        EntriesCompanion(
          pinned: Value(pinned),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }

  /// 按当前筛选条件取**全部**匹配 id（W15 多选）
  ///
  /// 为什么不复用 [watchTimeline]：时间轴有 `limit`（分页红线），
  /// 而「按筛选全选」的语义是"选中当前条件下**全部**记录"。
  /// 若按已加载的前 100 条来选，用户以为全选了、实际漏掉的是他根本看不见的那部分
  /// —— 这是最危险的一类静默错误（他可能随后就点了"删除"）。
  Future<List<int>> selectIdsByFilter({
    int? notebookId,
    String? type,
    bool pinnedOnly = false,
  }) async {
    final rows = await (select(entries)
          ..where((e) {
            var cond = e.deleted.equals(false) & e.status.equals('normal');
            if (notebookId != null) {
              cond = cond & e.notebookId.equals(notebookId);
            }
            if (type != null) cond = cond & e.type.equals(type);
            if (pinnedOnly) cond = cond & e.pinned.equals(true);
            return cond;
          }))
        .get();
    return rows.map((e) => e.id).toList(growable: false);
  }

  /// 批量软删（单事务）：语义与 [softDelete] 完全一致，只是一次处理多条。
  ///
  /// 为什么必须裹在一个事务里：批量删 30 条若中途失败，用户会停在"删了一半"的状态，
  /// 而他没有任何办法知道自己删到了哪一条 —— 要么全成，要么全不成。
  /// 已被删除的 id 会被跳过，返回值是**实际**受影响的条数。
  Future<int> softDeleteMany(List<int> ids) {
    if (ids.isEmpty) return Future.value(0);
    return transaction(() async {
      final rows = await (select(entries)
            ..where((e) => e.id.isIn(ids) & e.deleted.equals(false)))
          .get();
      if (rows.isEmpty) return 0;
      final now = DateTime.now();
      for (final row in rows) {
        await (update(entries)..where((e) => e.id.equals(row.id))).write(
          EntriesCompanion(
            deleted: const Value(true),
            updatedAt: Value(now),
            version: Value(row.version + 1),
          ),
        );
      }
      // FTS 清理同样要在本事务内完成：留下悬空的索引行会让搜索命中已删记录
      final placeholders = List.filled(rows.length, '?').join(',');
      await customStatement(
        'DELETE FROM entries_fts WHERE entry_id IN ($placeholders)',
        rows.map((e) => e.id).toList(growable: false),
      );
      return rows.length;
    });
  }

  /// 批量置顶 / 取消置顶（单事务，理由同 [softDeleteMany]）
  Future<int> setPinnedMany(List<int> ids, {required bool pinned}) {
    if (ids.isEmpty) return Future.value(0);
    return transaction(() async {
      final rows =
          await (select(entries)..where((e) => e.id.isIn(ids))).get();
      final now = DateTime.now();
      for (final row in rows) {
        await (update(entries)..where((e) => e.id.equals(row.id))).write(
          EntriesCompanion(
            pinned: Value(pinned),
            updatedAt: Value(now),
            version: Value(row.version + 1),
          ),
        );
      }
      return rows.length;
    });
  }

  /// 回收站**永久删除**（W7）：物理删除条目行，并清理它的全部附属数据。
  ///
  /// 顺序不能反：drift 默认开启外键约束，子表行必须先处理。
  /// - entry_tags / entries_fts：物理删（纯索引数据，无软删语义）
  /// - assets / todos：软删（保持数据红线"删除一律软删"，文件与行都留着可追溯）
  Future<void> hardDelete(int id) => transaction(() async {
        await _detachEntry(id);
        await (delete(entries)..where((e) => e.id.equals(id))).go();
      });

  /// 清空回收站（W7）：永久删除所有 deleted=true 的条目，返回清理条数
  Future<int> emptyTrash() => transaction(() async {
        final ids = await (select(entries)
              ..where((e) => e.deleted.equals(true)))
            .map((e) => e.id)
            .get();
        for (final id in ids) {
          await _detachEntry(id);
        }
        if (ids.isNotEmpty) {
          await (delete(entries)..where((e) => e.deleted.equals(true))).go();
        }
        return ids.length;
      });

  /// 清除某条目的附属数据（供 hardDelete / emptyTrash 在事务内复用）
  Future<void> _detachEntry(int id) async {
    await customStatement('DELETE FROM entry_tags WHERE entry_id = ?', [id]);
    await customStatement('DELETE FROM entries_fts WHERE entry_id = ?', [id]);
    await (update(assets)..where((a) => a.entryId.equals(id)))
        .write(const AssetsCompanion(deleted: Value(true)));
    // todos 不在本 accessor 的 tables 里（避免为一次软删扩大 accessor 面），
    // 走等价的裸 SQL；语义同样是软删，不物理删行。
    await customStatement('UPDATE todos SET deleted = 1 WHERE entry_id = ?', [id]);
  }

  /// 回收站 30 天清理：物理删除过期软删行及其 FTS 残留（§4.3 媒体清理策略）。
  /// 返回清理条数；每次启动时调用一次。
  Future<int> purgeExpiredTrash({int retainDays = 30}) {
    return transaction(() async {
      final cutoff =
          DateTime.now().subtract(Duration(days: retainDays));
      final expired = await (select(entries)
            ..where((e) => e.deleted.equals(true) & e.updatedAt.isSmallerThanValue(cutoff)))
          .get();
      for (final e in expired) {
        await _detachEntry(e.id);
      }
      if (expired.isNotEmpty) {
        await (delete(entries)
              ..where((e) => e.deleted.equals(true) &
                  e.updatedAt.isSmallerThanValue(cutoff)))
            .go();
      }
      return expired.length;
    });
  }

  /// FTS5 全文搜索：返回命中条目 id（按相关度）。
  Future<List<int>> searchEntryIds(String ftsQuery) async {
    final rows = await customSelect(
      'SELECT entry_id FROM entries_fts WHERE entries_fts MATCH ? '
      'ORDER BY rank LIMIT 50',
      variables: [Variable.withString(ftsQuery)],
      readsFrom: {attachedDatabase.entries},
    ).get();
    return rows.map((r) => r.read<int>('entry_id')).toList();
  }

  /// FTS 行写入（仅事务内部调用；外部统一走 [saveEntry]）
  Future<void> _upsertFtsRow(
      int entryId, String title, String contentText) async {
    await customStatement(
      'DELETE FROM entries_fts WHERE entry_id = ?',
      [entryId],
    );
    await customStatement(
      'INSERT INTO entries_fts (entry_id, title, content_text) '
      'VALUES (?, ?, ?)',
      [entryId, title, contentText],
    );
  }
}