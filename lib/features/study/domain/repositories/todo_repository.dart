import '../entities/study_todo.dart';

/// 学习待办仓库接口（实现见 data/todo_repository_impl.dart）
abstract interface class TodoRepository {
  /// 全部未删除待办：未完成优先，按优先级 + 截止时间排序
  Stream<List<StudyTodo>> watchTodos();

  /// 开关待办：完成时写 completedAt（§4.3 修正 ②）
  Future<void> setDone(int id, {required bool value});
}