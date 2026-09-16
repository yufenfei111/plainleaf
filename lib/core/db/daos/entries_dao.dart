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

  /// 时间轴流：未删除条目按「置顶优先 + 日期倒序」，流式联首图与笔记本
  Stream<List<TimelineRow>> watchTimeline({int limit = 100}) {
    final query = select(entries)
      ..where((e) => e.deleted.equals(false))
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