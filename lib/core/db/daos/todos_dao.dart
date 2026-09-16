import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'todos_dao.g.dart';

@DriftAccessor(tables: [Todos])
class TodosDao extends DatabaseAccessor<PlainLeafDatabase>
    with _$TodosDaoMixin {
  TodosDao(super.db);

  /// 今日待办流：未删除、未完成优先、按截止时间与优先级排序
  Stream<List<Todo>> watchTodos() {
    return (select(todos)
          ..where((t) => t.deleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.done),
            (t) => OrderingTerm.desc(t.priority),
            (t) => OrderingTerm.asc(t.dueDate),
          ]))
        .watch();
  }

  Future<int> insertTodo(TodosCompanion data) => into(todos).insert(data);

  /// 开关待办：完成时写 completedAt（§4.3 修正 ②，学习统计依赖）
  Future<void> setDone(int id, {required bool value}) {
    return transaction(() async {
      final row =
          await (select(todos)..where((t) => t.id.equals(id))).getSingle();
      await (update(todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          done: Value(value),
          completedAt: value ? Value(DateTime.now()) : const Value(null),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }
}