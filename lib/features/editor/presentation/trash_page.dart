import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../timeline/domain/entities/timeline_entry.dart';
import '../../timeline/presentation/providers/timeline_providers.dart';

/// 回收站（W7：恢复 / 永久删除 / 清空）
///
/// W3 只做了「逐条恢复」，回收站只增不减；W7 补齐删除侧：
/// 永久删除与清空都要二次确认——这一步不可撤销，是数据安全的最后一道闸。
class TrashPage extends ConsumerWidget {
  const TrashPage({super.key});

  static const int _retainDays = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trash = ref.watch(trashStreamProvider);
    final actions = ref.read(timelineActionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined),
            tooltip: '清空回收站',
            onPressed: () => _confirmEmpty(context, ref, actions),
          ),
        ],
      ),
      body: trash.when(
        data: (list) {
          if (list.isEmpty) {
            return const _EmptyView();
          }
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            itemCount: list.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return const _RetainNotice();
              return _TrashTile(entry: list[i - 1]);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
      ),
    );
  }

  Future<void> _confirmEmpty(
    BuildContext context,
    WidgetRef ref,
    TimelineActions actions,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空回收站？'),
        content: const Text(
          '回收站内的记录将被永久删除，无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final n = await actions.emptyTrash();
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('已永久删除 $n 条')));
    } on Exception catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('清空失败：$error')));
    }
  }
}

class _RetainNotice extends StatelessWidget {
  const _RetainNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        '删除的记录保留 30 天，到期自动清理',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).hintColor),
      ),
    );
  }
}

class _TrashTile extends ConsumerWidget {
  const _TrashTile({required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(timelineActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    // 剩余保留天数：以最后一次修改（即删除时间）为起点
    final passed = DateTime.now().difference(entry.updatedAt).inDays;
    final remain = (TrashPage._retainDays - passed).clamp(0, TrashPage._retainDays);

    return ListTile(
      leading: const Icon(Icons.delete_outline),
      title: Text(
        entry.title.isEmpty ? '(无标题)' : entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${entry.plainText.isEmpty ? '(无正文)' : entry.plainText} · '
        '还剩 $remain 天',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore, size: 20),
            tooltip: '恢复',
            onPressed: () async {
              try {
                await actions.restore(entry.id);
                if (!context.mounted) return;
                messenger.showSnackBar(const SnackBar(content: Text('已恢复')));
              } on Exception catch (error) {
                if (!context.mounted) return;
                messenger.showSnackBar(SnackBar(content: Text('恢复失败：$error')));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined, size: 20),
            tooltip: '永久删除',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('永久删除？'),
                  content: Text(
                    '「${entry.title.isEmpty ? '(无标题)' : entry.title}」将被彻底删除，无法恢复。',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              try {
                await actions.hardDelete(entry.id);
                if (!context.mounted) return;
                messenger.showSnackBar(const SnackBar(content: Text('已永久删除')));
              } on Exception catch (error) {
                if (!context.mounted) return;
                messenger.showSnackBar(SnackBar(content: Text('删除失败：$error')));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_sweep_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary.withAlpha(120)),
          const SizedBox(height: 12),
          Text('回收站是空的', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
