import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';

/// 时间轴首页（阶段 0 静态版 + Stream 实时数据）
/// 页面要素（计划书 §5.2）：日期锚点、图文卡片、心情色点、悬浮「+」
/// UI 走查三要素（§5.2 规范）：加载态 / 空态 / 错误态齐全。
class TimelinePage extends ConsumerWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);
    final timeline = db.entriesDao.watchTimeline();

    return Scaffold(
      appBar: AppBar(title: const Text('素页')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // W3 编辑器页接入后跳转编辑器；阶段 0 仅占位提示
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('编辑器将在 W3（MVP 阶段）接入')),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      body: StreamBuilder<List<TimelineRowData>>(
        stream: timeline.map(
          (rows) => rows
              .map((r) => TimelineRowData(
                    title: r.entry.title,
                    plainText: r.entry.plainText,
                    type: r.entry.type,
                    mood: r.entry.mood,
                    entryDate: r.entry.entryDate,
                    space: r.notebook?.space,
                    notebookName: r.notebook?.name,
                  ))
              .toList(),
        ),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _LoadingView();
          }
          if (snap.hasError) {
            return _ErrorView(error: '${snap.error}');
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return const _EmptyView();
          }
          return _TimelineList(rows: rows);
        },
      ),
    );
  }
}

/// 时间轴卡片数据（阶段 0 内部结构；W2 由 Repository 领域模型替代）
class TimelineRowData {
  final String title;
  final String plainText;
  final String type;
  final int? mood;
  final DateTime entryDate;
  final String? space;
  final String? notebookName;

  const TimelineRowData({
    required this.title,
    required this.plainText,
    required this.type,
    required this.entryDate,
    this.mood,
    this.space,
    this.notebookName,
  });
}

const _typeLabels = {
  'note': '笔记',
  'diary': '日记',
  'quick': '速记',
  'todo': '待办',
};

/// 心情 1-5 档色点（Material 色板映射，避免自定义色过多）
const _moodColors = <int, Color>{
  1: Color(0xFF90CAF9),
  2: Color(0xFFA5D6A7),
  3: Color(0xFFFFF59D),
  4: Color(0xFFFFCC80),
  5: Color(0xFFEF9A9A),
};

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.rows});

  final List<TimelineRowData> rows;

  @override
  Widget build(BuildContext context) {
    // 日期锚点分组：同日合并，倒序展示
    final groups = <String, List<TimelineRowData>>{};
    for (final r in rows) {
      final d = r.entryDate;
      final key =
          '${d.year}年${d.month.toString().padLeft(2, '0')}月${d.day.toString().padLeft(2, '0')}日';
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

class _EntryCard extends StatelessWidget {
  const _EntryCard(this.r);

  final TimelineRowData r;

  @override
  Widget build(BuildContext context) {
    final moodColor = r.mood == null ? null : _moodColors[r.mood!];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图文卡片左侧：首图占位（W4 图片管线接入后显示真实缩略图）
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                switch (r.type) {
                  'diary' => Icons.edit_note,
                  'quick' => Icons.bolt,
                  'todo' => Icons.check_circle_outline,
                  _ => Icons.sticky_note_2_outlined,
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
                          r.title.isEmpty ? '(无标题)' : r.title,
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
                          decoration:
                              BoxDecoration(color: moodColor, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.plainText.isEmpty ? '(无正文)' : r.plainText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _Chip(label: _typeLabels[r.type] ?? r.type),
                      if (r.notebookName != null) ...[
                        const SizedBox(width: 6),
                        _Chip(label: r.notebookName!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
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
              size: 56, color: Theme.of(context).colorScheme.primary.withAlpha(120)),
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