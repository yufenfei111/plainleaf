import '../../../core/db/daos/todos_dao.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/entities/study_todo.dart';
import '../domain/repositories/todo_repository.dart';

/// [TodoRepository] 的本地 Drift 实现
class LocalTodoRepository implements TodoRepository {
  const LocalTodoRepository(this._dao);

  final TodosDao _dao;

  @override
  Stream<List<StudyTodo>> watchTodos() {
    return _dao.watchTodos().map(
          (rows) => rows
              .map((t) => StudyTodo(
                    id: t.id,
                    content: t.content,
                    done: t.done,
                    createdAt: t.createdAt,
                    completedAt: t.completedAt,
                    dueDate: t.dueDate,
                    priority: t.priority,
                  ))
              .toList(growable: false),
        );
  }

  @override
  Future<void> setDone(int id, {required bool value}) async {
    try {
      await _dao.setDone(id, value: value);
    } on Exception catch (error) {
      throw DatabaseException('更新待办失败', cause: error);
    }
  }

  @override
  Future<int> addTodo(String content) async {
    try {
      return await _dao.addTodoWithContent(content);
    } on Object catch (error) {
      // 写库一律兜住：录入失败要变成页面上一句提示，而不是冒泡成未处理异常。
      throw DatabaseException('添加待办失败', cause: error);
    }
  }

  @override
  Future<void> softDeleteTodo(int id) async {
    try {
      await _dao.softDeleteTodo(id);
    } on Object catch (error) {
      throw DatabaseException('删除待办失败', cause: error);
    }
  }

  @override
  Future<void> restoreTodo(int id) async {
    try {
      await _dao.restoreTodo(id);
    } on Object catch (error) {
      throw DatabaseException('撤销删除失败', cause: error);
    }
  }
}
