import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../data/todo_repository_impl.dart';
import '../../domain/daily_completion.dart';
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

/// 今日完成概况（W12）
///
/// 为什么放在 Provider 而不是页面里现算：统计口径（哪条算今天）属于领域逻辑，
/// 收在 [dailyCompletion] 一处后，文案与进度条共用同一个数字，
/// 不会演化出「写 1/2 却画 60%」的两套算法。
///
/// 已知取舍：[DateTime.now] 只在流下发时取一次，App 一直开着跨过午夜不会自动
/// 重算——下一次待办变动就会刷新。为此起一个定时器属于过度设计，先不做。
final todayStatsProvider = Provider<DailyStats>((ref) {
  final todos = ref.watch(todosStreamProvider).valueOrNull;
  if (todos == null) return DailyStats.empty; // loading / error 时降级为空盘子
  return dailyCompletion(todos, DateTime.now());
});

/// 「已完成」段落是否展开（W11）
///
/// 为什么默认折叠：学习 Tab 的主战场是「还没做的事」，默认收起已完成的条目，
/// 滚动空间就完整留给待办；想回看再点一下标题展开，成本一次点击。
final todoDoneExpandedProvider = StateProvider<bool>((ref) => false);

/// 录入框焦点手柄（W11）
///
/// 为什么把 FocusNode 放进 Provider：空态的主行动按钮要把焦点送回顶部输入框，
/// 而按钮（列表子树）与输入框（页面顶部固定行）不在同一棵子树里，
/// 用一个受管 FocusNode 中转比穿透传递回调更短、也不会泄漏。
final todoComposerFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode();
  ref.onDispose(node.dispose);
  return node;
});

/// 写操作门面（W11，与时间轴侧 TimelineActions 同一套写法）
///
/// 页面只做两件事：调用这里的方法、把异常转成 SnackBar——错误处理的套路
/// 不在 Widget 里各写一遍。
final todoActionsProvider = Provider<TodoActions>((ref) {
  return TodoActions(ref.watch(todoRepositoryProvider));
});

class TodoActions {
  const TodoActions(this._repo);

  final TodoRepository _repo;

  /// 添加待办：返回新 id；空白内容返回 null，由 UI 出一句轻提示。
  ///
  /// 为什么返回 id 而不是 bool：调用方（撤销/后续编辑）可能需要定位这一条，
  /// 而「写没写成功」用 null 表达已经足够，不必再包一层结果对象。
  Future<int?> addTodo(String content) async {
    if (content.trim().isEmpty) return null;
    final id = await _repo.addTodo(content);
    return id == 0 ? null : id;
  }

  /// 软删：行仍在库里，配合 [restoreTodo] 实现「撤销」
  Future<void> deleteTodo(int id) => _repo.softDeleteTodo(id);

  Future<void> restoreTodo(int id) => _repo.restoreTodo(id);
}
