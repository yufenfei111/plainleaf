import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../timeline/presentation/providers/timeline_providers.dart';

/// 回收站（W3，issue #6）：软删除条目，可恢复；30 天过期由启动清理负责
class TrashPage extends ConsumerWidget {
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trash = ref.watch(trashStreamProvider);
    final repo = ref.read(timelineRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: trash.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('回收站是空的'));
          }
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  '删除的记录保留 30 天，之后自动清理',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor),
                ),
              ),
              for (final t in list)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(
                    t.title.isEmpty ? '(无标题)' : t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    t.plainText.isEmpty ? '(无正文)' : t.plainText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('恢复'),
                    onPressed: () => repo.restore(t.id),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
      ),
    );
  }
}