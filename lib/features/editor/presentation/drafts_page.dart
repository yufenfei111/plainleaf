import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/empty_state.dart';
import '../../timeline/presentation/providers/timeline_providers.dart';

/// 草稿箱（W3，issue #5）：draft 记录列表，点击继续编辑，可发布/丢弃
class DraftsPage extends ConsumerWidget {
  const DraftsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('草稿箱')),
      body: drafts.when(
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.edit_note,
              title: '没有草稿',
              subtitle: '新建一条记录，自动保存后会先进入草稿箱',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: [
              for (final d in list)
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: Text(
                    d.title.isEmpty ? '(无标题)' : d.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    d.plainText.isEmpty ? '(无正文)' : d.plainText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '丢弃草稿',
                    onPressed: () =>
                        ref.read(timelineRepositoryProvider).softDelete(d.id),
                  ),
                  onTap: () => context.push('/editor?id=${d.id}'),
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