import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../timeline/domain/entities/timeline_filter.dart';
import '../../timeline/presentation/providers/timeline_providers.dart';
import '../domain/entities/notebook_item.dart';
import 'providers/notebooks_providers.dart';

/// 笔记本 Tab（W5：issue #10 分类管理 + issue #11 标签管理）
/// 生活/学习双空间 + 自定义本 CRUD；标签多级（parentId）管理内嵌底部。
class NotebooksPage extends ConsumerWidget {
  const NotebooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(notebooksStreamProvider);
    final tags = ref.watch(tagsStreamProvider);
    final db = ref.read(dbProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('笔记本')),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建笔记本',
        onPressed: () => _createNotebookDialog(context, db),
        child: const Icon(Icons.create_new_folder_outlined),
      ),
      body: notebooks.when(
        data: (list) {
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              // 没有笔记本时给出统一空态引导；标签管理入口（下方）保持可用。
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.book_outlined,
                  title: '还没有笔记本',
                  subtitle: '点击下方「+」按钮新建你的第一本笔记本',
                )
              else
                for (final n in list) _NotebookTile(notebook: n),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('标签',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.new_label, size: 18),
                      label: const Text('新建标签'),
                      onPressed: () => _createTagDialog(context, db, null),
                    ),
                  ],
                ),
              ),
              if (tags case AsyncData(:final value))
                for (final t in value)
                  ListTile(
                    leading: const Icon(Icons.label_outline),
                    title: Text(t.name),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: '删除标签',
                      onPressed: () => db.tagsDao.softDelete(t.id),
                    ),
                    onTap: () => _renameTagDialog(context, db, t.id, t.name),
                  ),
              if (tags.isLoading == false && tags.value?.isEmpty == true)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('还没有标签'),
                ),
              const SizedBox(height: 96),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
      ),
    );
  }

  /// 对话框统一入口：只负责弹窗与拿到结果，**不碰页面路由**。
  ///
  /// 历史缺陷：三个对话框结尾都写了 `context.pop()`，而那个 context 是页面级
  /// 的（不是 dialog 内部的），等于在关闭弹窗后又把整个笔记本页弹掉——
  /// 用户建完一个笔记本会发现自己被踢回上一个页面。对话框只需 `Navigator.pop`
  /// 自己（由 showDialog 的 builder 内部 context 完成），外层不做任何 pop。
  Future<void> _createNotebookDialog(BuildContext context, db) async {
    final ctrl = TextEditingController();
    final space = <String>['custom'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('新建笔记本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ctrl, autofocus: true,
                  decoration: const InputDecoration(labelText: '名称')),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'life', label: Text('生活')),
                  ButtonSegment(value: 'study', label: Text('学习')),
                  ButtonSegment(value: 'custom', label: Text('自定义')),
                ],
                selected: {space.first},
                onSelectionChanged: (s) => setState(() => space[0] = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => context.pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => context.pop(true), child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await db.notebooksDao.create(
      uuid: const Uuid().v4(),
      name: ctrl.text.trim(),
      space: space.first,
    );
  }

  Future<void> _createTagDialog(BuildContext context, db, int? parentId) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(parentId == null ? '新建标签' : '新建子标签'),
        content: TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(labelText: '标签名')),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => context.pop(true), child: const Text('创建')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await db.tagsDao.create(
        uuid: const Uuid().v4(),
        name: ctrl.text.trim(),
      );
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('创建失败：名称可能已存在')));
      }
    }
  }

  Future<void> _renameTagDialog(BuildContext context, db, int id, String old) async {
    final ctrl = TextEditingController(text: old);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => context.pop(true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await db.tagsDao.rename(id, ctrl.text.trim());
  }
}

/// 笔记本行（W10）：角标取自整页一次性的计数流，行内不再单独查库。
/// 点击行为补全——此前是空的 onTap，点下去毫无反应；现在跳到时间轴并按该本筛选。
class _NotebookTile extends ConsumerWidget {
  const _NotebookTile({required this.notebook});

  final NotebookItem notebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    final count = ref.watch(notebookCountsProvider).valueOrNull?[notebook.id] ?? 0;
    return ListTile(
      leading: Icon(
        notebook.space == 'study'
            ? Icons.school_outlined
            : notebook.space == 'life'
                ? Icons.home_outlined
                : Icons.folder_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(notebook.name),
      subtitle: notebook.space == 'custom' ? const Text('自定义') : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count 条',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor)),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: '删除笔记本',
            onPressed: () => db.notebooksDao.softDelete(notebook.id),
          ),
        ],
      ),
      onTap: () {
        // 语义：「看这本里的内容」——设好筛选再回时间轴，比空转更符合直觉
        ref.read(timelineFilterProvider.notifier).state =
            TimelineFilter(notebookId: notebook.id);
        context.go('/timeline');
      },
    );
  }
}