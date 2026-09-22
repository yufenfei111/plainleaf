import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'notebooks_dao.g.dart';

@DriftAccessor(tables: [Notebooks])
class NotebooksDao extends DatabaseAccessor<PlainLeafDatabase>
    with _$NotebooksDaoMixin {
  NotebooksDao(super.db);

  /// 笔记本流（含空间分组所需的全部字段，UI 按 space 分组）
  Stream<List<Notebook>> watchNotebooks() {
    return (select(notebooks)
          ..where((n) => n.deleted.equals(false))
          ..orderBy([(n) => OrderingTerm.asc(n.sortIndex)]))
        .watch();
  }

  Future<int> insertNotebook(NotebooksCompanion data) =>
      into(notebooks).insert(data);

  /// 创建自定义笔记本（W5，issue #10）
  Future<int> create({required String uuid, required String name, required String space, int? color}) {
    return into(notebooks).insert(NotebooksCompanion.insert(
      uuid: uuid,
      name: Value(name),
      space: Value(space),
      coverColor: Value(color),
      sortIndex: const Value(99),
    ));
  }

  /// 重命名（version 递增）
  Future<void> rename(int id, String name) {
    return transaction(() async {
      final row =
          await (select(notebooks)..where((n) => n.id.equals(id))).getSingle();
      await (update(notebooks)..where((n) => n.id.equals(id))).write(
        NotebooksCompanion(
          name: Value(name),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }

  /// 软删除笔记本
  Future<void> softDelete(int id) {
    return transaction(() async {
      final row =
          await (select(notebooks)..where((n) => n.id.equals(id))).getSingle();
      await (update(notebooks)..where((n) => n.id.equals(id))).write(
        NotebooksCompanion(
          deleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }

  /// 一次性统计**全部**笔记本下的条目数（W10 性能修复）
  ///
  /// 原实现是每个 tile 各自 FutureBuilder 调 [countEntries]：
  /// ① N 个笔记本 = N 次查询；② FutureBuilder 每次 rebuild 都重建 Future，
  /// 页面任意一次刷新（切 Tab、键盘弹出、流推送）都会把 N 次查询重放一遍，
  /// 角标还会先闪回 0 再跳到真实值。改成一条 GROUP BY，且走 watch 保持实时。
  Stream<Map<int, int>> watchEntryCountsByNotebook() {
    final count = db.entries.id.count();
    final query = selectOnly(db.entries)
      ..addColumns([db.entries.notebookId, count])
      ..where(db.entries.deleted.equals(false) &
          db.entries.status.equals('normal'))
      ..groupBy([db.entries.notebookId]);
    return query.watch().map((rows) => <int, int>{
          for (final row in rows)
            if (row.read(db.entries.notebookId) case final int id)
              id: row.read(count) ?? 0,
        });
  }

  /// 笔记本下未删除条目数（列表角标）
  Future<int> countEntries(int notebookId) {
    final count = db.entries.id.count();
    final q = selectOnly(db.entries)
      ..addColumns([count])
      ..where(db.entries.notebookId.equals(notebookId) &
          db.entries.deleted.equals(false) &
          db.entries.status.equals('normal'));
    return q.map((row) => row.read(count) ?? 0).getSingle();
  }
}