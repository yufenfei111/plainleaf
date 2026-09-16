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
}