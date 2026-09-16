import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/notebook_item.dart';
import 'providers/notebooks_providers.dart';

/// 笔记本 Tab（W2：Repository + Riverpod AsyncValue 接入）
/// 生活/学习双空间分组展示；标签管理与自定义本 CRUD 在 W5 接入。
class NotebooksPage extends ConsumerWidget {
  const NotebooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(notebooksStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('笔记本')),
      body: notebooks.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('还没有笔记本'));
          }
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: [
              for (final n in list) _NotebookTile(notebook: n),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
      ),
    );
  }
}

class _NotebookTile extends StatelessWidget {
  const _NotebookTile({required this.notebook});

  final NotebookItem notebook;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        notebook.space == 'study' ? Icons.school_outlined : Icons.home_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(notebook.name),
      subtitle: notebook.space == 'custom' ? const Text('自定义') : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        // W5 接入笔记本详情
      },
    );
  }
}