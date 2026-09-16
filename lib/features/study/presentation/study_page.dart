import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';

/// 学习 Tab（阶段 0）：待办清单已接数据库 Stream（可勾选、实时落库）
/// 番茄钟/统计图表按路线图 W11–W12 接入。
class StudyPage extends ConsumerWidget {
  const StudyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('学习')),
      body: StreamBuilder(
        stream: db.todosDao.watchTodos().map((list) => list
            .map((t) => TodoRow(id: t.id, content: t.content, done: t.done))
            .toList()),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final todos = snap.data ?? const <TodoRow>[];
          if (todos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_alt,
                      size: 56,
                      color:
                          Theme.of(context).colorScheme.primary.withAlpha(120)),
                  const SizedBox(height: 12),
                  Text('今天没有待办', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'W11 待办录入上线后，在这里安排学习计划',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: [
              for (final t in todos)
                CheckboxListTile(
                  value: t.done,
                  onChanged: (v) =>
                      db.todosDao.setDone(t.id, value: v ?? false),
                  title: Text(
                    t.content,
                    style: TextStyle(
                      decoration:
                          t.done ? TextDecoration.lineThrough : null,
                      color: t.done ? Theme.of(context).hintColor : null,
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 行视图：避免 UI 直接命名生成的表类（分层红线），W2 Repository 领域模型替代
class TodoRow {
  final int id;
  final String content;
  final bool done;

  const TodoRow(
      {required this.id, required this.content, required this.done});
}