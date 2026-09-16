import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';

/// 笔记本 Tab（阶段 0）：生活/学习双空间分组展示（数据来自数据库 Stream）
/// 标签管理、自定义笔记本 CRUD 在 W5 接入。
class NotebooksPage extends ConsumerWidget {
  const NotebooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('笔记本')),
      body: StreamBuilder(
        stream: db.notebooksDao.watchNotebooks(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('还没有笔记本'));
          }
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: [
              for (final n in items)
                ListTile(
                  leading: Icon(
                    n.space == 'study'
                        ? Icons.school_outlined
                        : Icons.home_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(n.name),
                  subtitle: n.space == 'custom' ? const Text('自定义') : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // W5 接入笔记本详情
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}