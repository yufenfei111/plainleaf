import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../data/todo_repository_impl.dart';
import '../../domain/entities/study_todo.dart';
import '../../domain/repositories/todo_repository.dart';

/// 待办仓库（UI → Provider → Repository → DAO 分层链路）
final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return LocalTodoRepository(ref.watch(dbProvider).todosDao);
});

/// 待办数据流（页面 .when 消费三态）
final todosStreamProvider = StreamProvider<List<StudyTodo>>((ref) {
  return ref.watch(todoRepositoryProvider).watchTodos();
});