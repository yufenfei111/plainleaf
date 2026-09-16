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
  /// 注：资产/笔记本变更暂不触发重算，W2 Repository 层统一优化（阶段 0 演示够用）
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

  /// FTS5 全文搜索：返回命中条目 id（按相关度）
  /// FTS5 query 语法由调用方转义；W2 Repository 双写后此助手接入 search feature
  Future<List<int>> searchEntryIds(String ftsQuery) async {
    final rows = await customSelect(
      'SELECT entry_id FROM entries_fts WHERE entries_fts MATCH ? '
      'ORDER BY rank LIMIT 50',
      variables: [Variable.withString(ftsQuery)],
      readsFrom: {attachedDatabase.entries},
    ).get();
    return rows.map((r) => r.read<int>('entry_id')).toList();
  }

  /// 插入/更新 FTS 行（供种子与 W2 Repository 双写复用）
  Future<void> upsertFtsRow(int entryId, String title, String contentText) async {
    await customStatement(
      'DELETE FROM entries_fts WHERE entry_id = ?', [entryId],
    );
    await customStatement(
      'INSERT INTO entries_fts (entry_id, title, content_text) VALUES (?, ?, ?)',
      [entryId, title, contentText],
    );
  }
  /// 插入一条记录（演示数据；W2 Repository 将在此做 entries + entries_fts 事务双写）
  Future<int> insertEntry(EntriesCompanion data) => into(entries).insert(data);

  /// 软删除（数据红线：一律软删除，version 递增）
  /// 读-改-写放同一事务；W2 Repository 层会在此同时双写 entries_fts。
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
    });
  }
}