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

@DriftAccessor(tables: [Entries, Assets, Notebooks])
class EntriesDao extends DatabaseAccessor<PlainLeafDatabase>
    with _$EntriesDaoMixin {
  EntriesDao(super.db);

  /// 时间轴流：未删除、非草稿条目，置顶优先 + 日期倒序，流式联首图与笔记本
  Stream<List<TimelineRow>> watchTimeline({int limit = 100}) {
    final query = select(entries)
      ..where((e) => e.deleted.equals(false) & e.status.equals('normal'))
      ..orderBy([
        (e) => OrderingTerm.desc(e.pinned),
        (e) => OrderingTerm.desc(e.entryDate),
      ])
      ..limit(limit);

    return query.watch().asyncMap((entryList) async {
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
        await customStatement(
            'DELETE FROM entries_fts WHERE entry_id = ?', [e.id]);
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