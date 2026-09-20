import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

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
    final root = ref.watch(supportDirProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('素页'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => context.push('/search'),
          ),
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
            : _TimelineList(entries: entries, root: root),
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
  const _TimelineList({required this.entries, this.root});

  final List<TimelineEntry> entries;

  /// App 支持目录（相对路径的解析基准）；为 null 表示尚未取到
  final String? root;

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
      // 预渲染视口外的缓冲：滑动时提前备好下一屏，减少"边滑边建"的抖动
      // （Flutter 3.41+ 用 ScrollCacheExtent；这里按视口倍数给，比写死像素更适配大屏）
      scrollCacheExtent: const ScrollCacheExtent.viewport(1.0),
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
            for (final r in groups[key]!) _EntryCard(r, root: root),
          ],
        );
      },
    );
  }
}

/// 列表缩略图（W6 性能改造）
/// 三处关键点，缺一个都会让滑动掉帧：
/// 1. **优先用 thumb 而不是原图**：52dp 的框里解码 4000×3000 的原图，
///    单张就吃掉几十 MB 解码内存，是列表卡顿的头号来源；
/// 2. **cacheWidth 限制解码尺寸**：即使回退到原图，也只按显示尺寸×DPR 解码，
///    不让引擎把整张图摊开；
/// 3. **路径同步拼接**：root 由上层 provider 给，卡片内不再发起 Future。
class _ThumbTile extends StatelessWidget {
  const _ThumbTile({required this.rel, required this.root, required this.size});

  final String rel;
  final String? root;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (root == null) {
      return const SizedBox.expand();
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.file(
      File(p.join(root!, rel)),
      fit: BoxFit.cover,
      // 按显示尺寸解码（×设备像素比），避免解码整张原图
      cacheWidth: (size * dpr).round(),
      // 解码失败/文件缺失不再抛红屏，回退占位色块
      errorBuilder: (_, _, _) => const SizedBox.expand(),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard(this.entry, {this.root});

  final TimelineEntry entry;

  /// App 支持目录（null 时图片位显示占位色块，不发起异步）
  final String? root;

  @override
  Widget build(BuildContext context) {
    final moodColor = entry.mood == null ? null : _moodColors[entry.mood!];
    // 有缩略图用缩略图，没有（W4 期历史数据）回退原图，但解码尺寸仍受限
    final thumbRel = entry.firstAssetThumbPath ?? entry.firstAssetRelPath;
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
                child: thumbRel != null
                    ? _ThumbTile(rel: thumbRel, root: root, size: 52)
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