import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/skeleton.dart';
import '../domain/entities/study_todo.dart';
import 'providers/study_providers.dart';

/// 学习 Tab（W2 接流 → W11 补录入/分组/软删）
class StudyPage extends ConsumerWidget {
  const StudyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todosStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('学习')),
      // 录入行固定在 body 顶部（不随列表滚动）：加一行是高频动作，
      // 键盘弹起时它也必须在原位，否则「写一半输入框漂走」最伤手感。
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: _Composer(),
          ),
          Expanded(
            child: todos.when(
              data: (list) => _TodoBody(todos: list),
              loading: () => const _TodoSkeleton(),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: '待办没能加载出来',
                subtitle: '$error',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部录入行：TextField + 添加按钮，回车即添加。
///
/// 为什么不做成弹窗/二级页面：录入是「顺手加一行」，多一次跳转等于把
/// 一秒钟能做完的事变成三次点击；就地录入才能真的用起来。
class _Composer extends ConsumerStatefulWidget {
  const _Composer();

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      final id = await ref.read(todoActionsProvider).addTodo(_controller.text);
      if (!mounted) return;
      if (id == null) {
        // 空输入/纯空格不算错误：给一句提示就够，不弹窗、不打断。
        _showSnack('先写点内容，再添加');
        return;
      }
      _controller.clear();
      // 关掉键盘：连续录入时手不该还得按一次返回键。
      FocusScope.of(context).unfocus();
    } on Object catch (error) {
      if (mounted) _showSnack('添加失败：$error');
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: ref.watch(todoComposerFocusProvider),
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: '添加一件要做的事',
              hintStyle: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '添加待办',
          onPressed: _submit,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// 列表正文：未完成在上、已完成折叠在下，各带条数
class _TodoBody extends ConsumerWidget {
  const _TodoBody({required this.todos});

  final List<StudyTodo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = <StudyTodo>[];
    final done = <StudyTodo>[];
    for (final t in todos) {
      (t.done ? done : pending).add(t);
    }
    // 同优先级下新写的排最上面：刚录完抬头就该看见自己那条，
    // 而不是让它沉到底部让人怀疑没写进去。
    pending.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      return byPriority != 0 ? byPriority : b.createdAt.compareTo(a.createdAt);
    });

    if (todos.isEmpty) {
      return EmptyState(
        icon: Icons.task_alt,
        title: '还没有安排学习任务',
        subtitle: '在上方输入框写下第一件要做的事，回车就能添加',
        actionLabel: '回到输入框',
        onAction: () => ref.read(todoComposerFocusProvider).requestFocus(),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: _AllDoneHint(),
          )
        else ...[
          _SectionHeader(label: '未完成', count: pending.length),
          for (final t in pending) _TodoTile(todo: t, dismissible: true),
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: 8),
          // 没有未完成项时强制展开：否则「全部完成」看起来像丢数据。
          _DoneSection(todos: done, forceExpanded: pending.isEmpty),
        ],
      ],
    );
  }
}

/// 「全部完成」说明文案（不是空态：下面还有已完成段落，用轻量提示就够了）
class _AllDoneHint extends StatelessWidget {
  const _AllDoneHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.check_circle_outline,
            size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '没有未完成的事了，收工或再加一条',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 已完成段落：点标题展开/折叠
class _DoneSection extends ConsumerWidget {
  const _DoneSection({required this.todos, required this.forceExpanded});

  final List<StudyTodo> todos;
  final bool forceExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expanded = forceExpanded || ref.watch(todoDoneExpandedProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () =>
              ref.read(todoDoneExpandedProvider.notifier).state = !expanded,
          child: Padding(
            // 上下留到 12dp：整行点击区 ≥44dp，折叠按钮不比列表项难按。
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Text(
                  '已完成',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 6),
                Text(
                  '${todos.length}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final t in todos) _TodoTile(todo: t, dismissible: false),
      ],
    );
  }
}

/// 单条待办：未完成可左滑软删，勾选在 setDone
class _TodoTile extends ConsumerWidget {
  const _TodoTile({required this.todo, required this.dismissible});

  final StudyTodo todo;
  final bool dismissible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = CheckboxListTile(
      value: todo.done,
      onChanged: (v) async {
        try {
          await ref
              .read(todoRepositoryProvider)
              .setDone(todo.id, value: v ?? false);
        } on Object catch (error) {
          if (context.mounted) _showSnack(context, '更新失败：$error');
        }
      },
      title: Text(
        todo.content,
        style: TextStyle(
          decoration: todo.done ? TextDecoration.lineThrough : null,
          color: todo.done ? Theme.of(context).hintColor : null,
        ),
      ),
      controlAffinity: ListTileControlAffinity.leading,
    );

    if (!dismissible) return tile;

    final colorScheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey<int>(todo.id),
      direction: DismissDirection.endToStart,
      // 统一 200ms：与全 App 的过渡节奏保持一致，不做自定义曲线。
      resizeDuration: const Duration(milliseconds: 200),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: colorScheme.errorContainer,
        child: Icon(Icons.delete_outline, color: colorScheme.onErrorContainer),
      ),
      // 先写库再决定是否真的滑走：写失败就让这一行弹回来，
      // 避免出现「UI 删了、库里还在」的鬼影。
      confirmDismiss: (direction) async {
        try {
          await ref.read(todoActionsProvider).deleteTodo(todo.id);
          return true;
        } on Object catch (error) {
          if (context.mounted) _showSnack(context, '删除失败：$error');
          return false;
        }
      },
      onDismissed: (_) => _showUndoSnack(context, ref, todo),
      child: tile,
    );
  }
}

/// 删除后的「撤销」提示：软删的意义就在这里——留一条回头路
void _showUndoSnack(BuildContext context, WidgetRef ref, StudyTodo todo) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text('已删除「${todo.content}」'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            try {
              await ref.read(todoActionsProvider).restoreTodo(todo.id);
            } on Object catch (error) {
              if (context.mounted) _showSnack(context, '撤销失败：$error');
            }
          },
        ),
      ),
    );
}

void _showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
}

/// 列表骨架（loading 态）
///
/// 为什么不用转圈：和占位的真实行一样高的话，数据到位时布局不跳变；
/// 也不引入循环动画——它既违背「动画克制」，也会让测试里的 settle 永远等不到静止。
class _TodoSkeleton extends StatelessWidget {
  const _TodoSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '加载中',
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        itemCount: 6,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const SkeletonBox(width: 24, height: 24, radius: 4),
              const SizedBox(width: 16),
              Expanded(
                child: SkeletonBox(
                  width: (i % 2 == 0) ? double.infinity : 180,
                  height: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
