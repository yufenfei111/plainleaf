import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

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

  /// 录入入口（W11）：写一条待办，返回新自增 id；空白内容返回 0 表示没写。
  ///
  /// 为什么 uuid 在 DAO 里生成：uuid 属于「全表统一五字段」的同步预留约定（§4.3），
  /// 交给上层拼就等于把数据层契约漏进 UI，且各调用方极易漏写或写重复。
  ///
  /// 为什么 trim 后的空串直接返回 0 而不是报错：录入是一次「顺手加一行」的动作，
  /// 手滑敲个空格不该被当成错误打断；由 UI 出一句轻提示即可。
  Future<int> addTodoWithContent(String content) async {
    final text = content.trim();
    if (text.isEmpty) return 0;
    return transaction(() async {
      return into(todos).insert(
        TodosCompanion.insert(uuid: const Uuid().v4(), content: text),
      );
    });
  }

  /// 软删（§4.3 红线：删除一律软删，行留在库里可追溯、可撤销）
  Future<void> softDeleteTodo(int id) => _markDeleted(id, deleted: true);

  /// 撤销删除：SnackBar「撤销」走的同一条路径，version 继续 +1
  Future<void> restoreTodo(int id) => _markDeleted(id, deleted: false);

  Future<void> _markDeleted(int id, {required bool deleted}) {
    return transaction(() async {
      final row =
          await (select(todos)..where((t) => t.id.equals(id))).getSingle();
      await (update(todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          deleted: Value(deleted),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }

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