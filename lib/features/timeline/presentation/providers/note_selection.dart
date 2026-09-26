import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/timeline_filter.dart';
import 'timeline_providers.dart';

/// 时间轴多选状态（W15 需求 2）
class NoteSelection {
  const NoteSelection({this.active = false, this.ids = const <int>{}});

  /// 是否处于「选择模式」：true 时卡片点击 = 切换选中，而不是进详情
  final bool active;

  /// 已选记录 id
  final Set<int> ids;

  int get count => ids.length;

  bool get hasAny => ids.isNotEmpty;

  bool contains(int id) => ids.contains(id);

  NoteSelection copyWith({bool? active, Set<int>? ids}) => NoteSelection(
        active: active ?? this.active,
        ids: ids ?? this.ids,
      );
}

/// 多选控制器
///
/// 为什么把状态放进 Provider 而不是页面 State：
/// ① AppBar、筛选条、每张卡片三处都要读写它，放 State 就得层层传回调；
/// ② 退出选择模式、清空、筛选变化复位，统一收在一个地方，不会漏掉某个分支。
class NoteSelectionController extends Notifier<NoteSelection> {
  @override
  NoteSelection build() {
    // **筛选条件一变就清空已选**。这条是安全约束而不是交互偏好：
    // 用户先选了 5 条 → 换一个筛选 → 已选里那 5 条多数已不在屏幕上，
    // 此时他点「删除」，删掉的是自己根本看不见的记录。宁可让他重选一次。
    ref.listen<TimelineFilter>(timelineFilterProvider, (previous, next) {
      if (previous == next) return;
      if (!state.active && !state.hasAny) return;
      state = const NoteSelection();
    });
    return const NoteSelection();
  }

  /// 进入选择模式（不预选任何一条）—— AppBar 上的「多选」按钮用
  void enter() => state = const NoteSelection(active: true);

  /// 进入选择模式并选中这一条（长按卡片触发）
  void start(int id) => state = NoteSelection(active: true, ids: <int>{id});

  void toggle(int id) {
    final ids = Set<int>.of(state.ids);
    if (!ids.remove(id)) ids.add(id);
    state = state.copyWith(ids: ids);
  }

  /// 按条件批量选中（替换式，不是追加）
  void selectAll(Iterable<int> ids) =>
      state = NoteSelection(active: true, ids: Set<int>.of(ids));

  void clearAll() => state = state.copyWith(ids: const <int>{});

  void exit() => state = const NoteSelection();
}

final noteSelectionProvider =
    NotifierProvider<NoteSelectionController, NoteSelection>(
        NoteSelectionController.new);
