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
}