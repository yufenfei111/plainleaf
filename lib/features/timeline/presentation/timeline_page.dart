import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/entities/timeline_entry.dart';
import '../../../../app/providers.dart';
import 'providers/timeline_providers.dart';

/// 时间轴首页（W3：编辑器/草稿箱/回收站全链路接入）
/// 页面要素（计划书 §5.2）：日期锚点、图文卡片、心情色点、悬浮「+」
/// 走查三要素：loading / empty / error 三态齐全。
class TimelinePage extends ConsumerWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = ref.watch(timelineStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('素页'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '草稿箱',
            onPressed: () => context.push('/drafts'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '回收站',
            onPressed: () => context.push('/trash'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/editor'),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      body: timeline.when(
        data: (entries) => entries.isEmpty
            ? const _EmptyView()
            : _TimelineList(entries: entries),
        loading: () => const _LoadingView(),
        error: (error, _) => _ErrorView(error: '$error'),
      ),
    );
  }
}

/// 心情 1–5 档色点（Material 色板映射，避免自定义色过多）
const _moodColors = <int, Color>{
  1: Color(0xFF90CAF9),
  2: Color(0xFFA5D6A7),
  3: Color(0xFFFFF59D),
  4: Color(0xFFFFCC80),
  5: Color(0xFFEF9A9A),
};

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    // 日期锚点分组：同日合并，倒序展示
    final groups = <String, List<TimelineEntry>>{};
    for (final r in entries) {
      final d = r.entryDate;
      final key = '${d.year}年${d.month.toString().padLeft(2, '0')}月'
          '${d.day.toString().padLeft(2, '0')}日';
      groups.putIfAbsent(key, () => []).add(r);
    }
    final keys = groups.keys.toList(growable: false);

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final key = keys[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                key,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            for (final r in groups[key]!) _EntryCard(r),
          ],
        );
      },
    );
  }
}

class _EntryCard extends ConsumerWidget {
  const _EntryCard(this.entry);

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moodColor = entry.mood == null ? null : _moodColors[entry.mood!];
    return Card(
      // 点击卡片进入编辑器继续编辑（W3 记录内核）
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/editor?id=${entry.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 图文卡片左侧：首图缩略图（W4 真实图片；无图时类型图标）
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: entry.firstAssetRelPath != null
                    ? FutureBuilder<File>(
                        future: ref
                            .read(mediaStorageProvider)
                            .resolve(entry.firstAssetRelPath!),
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done ||
                              !snap.hasData ||
                              !snap.data!.existsSync()) {
                            return const Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          return Image.file(snap.data!, fit: BoxFit.cover);
                        },
                      )
                    : Icon(
                        switch (entry.type) {
                          EntryType.diary => Icons.edit_note,
                          EntryType.quick => Icons.bolt,
                          EntryType.todo => Icons.check_circle_outline,
                          EntryType.note => Icons.sticky_note_2_outlined,
                        },
                        color: Theme.of(context).colorScheme.primary,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title.isEmpty ? '(无标题)' : entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (moodColor != null)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: moodColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.plainText.isEmpty ? '(无正文)' : entry.plainText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _Chip(label: entry.type.label),
                        if (entry.notebookName != null) ...[
                          const SizedBox(width: 6),
                          _Chip(label: entry.notebookName!),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
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
          Icon(Icons.spa_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary.withAlpha(120)),
          const SizedBox(height: 12),
          Text('还没有记录', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '点右下角「记一笔」，写下第一条',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
          ),
        ],
      ),
    );
  }
}