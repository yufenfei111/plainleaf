import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/empty_state.dart';
import '../domain/entities/study_todo.dart';
import 'providers/study_providers.dart';

/// 学习 Tab（W2：Repository + Riverpod AsyncValue 接入）
/// 待办清单已接数据库 Stream（可勾选、实时落库）；番茄钟/统计图表按路线图 W11–W12 接入。
class StudyPage extends ConsumerWidget {
  const StudyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todosStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('学习')),
      body: todos.when(
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.task_alt,
                title: '今天没有待办',
                subtitle: 'W11 待办录入上线后，在这里安排学习计划',
              )
            : _TodoList(todos: list),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
      ),
    );
  }
}

class _TodoList extends ConsumerWidget {
  const _TodoList({required this.todos});

  final List<StudyTodo> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      children: [
        for (final t in todos)
          CheckboxListTile(
            value: t.done,
            onChanged: (v) =>
                ref.read(todoRepositoryProvider).setDone(t.id, value: v ?? false),
            title: Text(
              t.content,
              style: TextStyle(
                decoration: t.done ? TextDecoration.lineThrough : null,
                color: t.done ? Theme.of(context).hintColor : null,
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
      ],
    );
  }
}
