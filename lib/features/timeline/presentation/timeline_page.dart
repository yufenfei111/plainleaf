import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../domain/entities/timeline_entry.dart';
import '../domain/entities/timeline_filter.dart';
import '../domain/timeline_grouping.dart';
import '../../../app/providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../detail/presentation/entry_detail_page.dart' show entryThumbHeroTag;
import '../../notebooks/presentation/providers/notebooks_providers.dart';
import 'providers/timeline_providers.dart';

/// 时间轴首页（W7：月分组 + 筛选器 + 置顶收藏）
///
/// 页面要素（计划书 §5.2）：月/日锚点、图文卡片、心情色点、悬浮「+」
/// 走查三要素：loading / empty / error 三态齐全；筛选后无结果另有空态。
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
            // 原来用 edit_note，与「写新记录」的语义混在一起；drafts 图标更贴切
            icon: const Icon(Icons.drafts_outlined),
            tooltip: '草稿箱',
            onPressed: () => context.push('/drafts'),
          ),
          IconButton(
            // delete_outline 看着像「删除当前内容」，实际入口是回收站
            icon: const Icon(Icons.restore_from_trash),
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
      body: Column(
        children: [
          const _FilterBar(),
          Expanded(
            child: _TimelineBody(state: timeline, root: root),
          ),
        ],
      ),
    );
  }
}

/// 列表区三态分发（W11）
///
/// 为什么不用 `AsyncValue.when`：续拉时 Riverpod 会把状态置成
/// `AsyncLoading(hasValue: true)`（保留了上一页数据），而 `when` 在 isLoading 时
/// 走的是 loading 分支——那会把已经渲染出来的列表推翻回骨架屏，
/// 用户滑到第 N 条的位置也一起丢了。所以这里按「有没有值」先分流。
class _TimelineBody extends ConsumerWidget {
  const _TimelineBody({required this.state, this.root});

  final AsyncValue<List<TimelineEntry>> state;

  /// App 支持目录（相对路径的解析基准）
  final String? root;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = state.valueOrNull;
    if (entries == null) {
      if (state.hasError) {
        return _ErrorView(error: '${state.error}');
      }
      return const TimelineSkeleton();
    }
    if (entries.isEmpty) {
      return _buildEmptyState(
          context, ref, ref.watch(timelineFilterProvider).isEmpty);
    }
    return _TimelineList(
      entries: entries,
      root: root,
      loading: state.isLoading,
    );
  }
}

/// 筛选入口（W11 重做）
///
/// 为什么从「横向无限滚动的 chip 条」改成「一个入口 + 底部弹层」：
/// 笔记本只会越建越多，横向条里同时可见的永远只有两三个，用户得靠横向摸索
/// 才知道自己有哪些可选条件；入口 + 弹层把可选项纵向一次性摊开，且能滚动。
///
/// 依然只改 `timelineFilterProvider` 一个状态，流会自动带着新的 where 重查——
/// UI 不做任何客户端过滤，避免"先 LIMIT 再筛"导致的假空列表。
class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(timelineFilterProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          _FilterEntryButton(
            count: filter.activeCount,
            onTap: () => _openFilterSheet(context),
          ),
          const Spacer(),
          if (!filter.isEmpty)
            TextButton(
              onPressed: () => ref
                  .read(timelineFilterProvider.notifier)
                  .update((_) => const TimelineFilter()),
              child: const Text('清除'),
            ),
        ],
      ),
    );
  }
}

/// 「筛选」入口按钮：有已选条件时右侧带一个数量小圆标
class _FilterEntryButton extends StatelessWidget {
  const _FilterEntryButton({required this.count, required this.onTap});

  /// 已激活的筛选条件个数；0 表示无筛选
  final int count;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = count > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        // 触控目标红线 ≥44dp
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : cs.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: active ? cs.primary : cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_outlined,
              size: 18,
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              '筛选',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: active ? cs.onPrimaryContainer : cs.onSurface,
                  ),
            ),
            if (active) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$count',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: cs.onPrimary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _openFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _FilterSheet(),
  );
}

/// 筛选弹层（W11）：笔记本 / 类型 / 仅看置顶三段 + 重置 / 查看结果。
///
/// 弹层内改的是**草稿**，点「查看结果」才写回 provider——
/// 否则每点一下 chip 就带着新 where 重查一次流，弹层里连续点几下会连着重查，
/// 既浪费 IO 也让列表在底下不停跳。
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late TimelineFilter draft;

  @override
  void initState() {
    super.initState();
    draft = ref.read(timelineFilterProvider);
  }

  void _update(TimelineFilter next) => setState(() => draft = next);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final notebooks = ref.watch(notebooksStreamProvider);

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('筛选', style: tt.titleMedium),
            ),
            // ── 笔记本 ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '笔记本',
                style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.book_outlined),
              title: const Text('全部笔记本'),
              trailing: draft.notebookId == null
                  ? Icon(Icons.check, color: cs.primary)
                  : null,
              onTap: () => _update(draft.copyWith(clearNotebook: true)),
            ),
            ...notebooks.when(
              data: (list) => [
                for (final n in list)
                  ListTile(
                    title: Text(n.name),
                    trailing: draft.notebookId == n.id
                        ? Icon(Icons.check, color: cs.primary)
                        : null,
                    onTap: () => _update(draft.copyWith(notebookId: n.id)),
                  ),
              ],
              loading: () => const <Widget>[],
              error: (_, _) => const <Widget>[],
            ),
            const Divider(height: 1),
            // ── 类型 ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '类型',
                style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final t in EntryType.values)
                    FilterChip(
                      label: Text(t.label),
                      selected: draft.type == t,
                      // 再点一次同一个 chip = 取消该条件
                      onSelected: (v) => _update(
                        draft.copyWith(type: t, clearType: !v),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── 仅看置顶 ────────────────────────────────────────────
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('仅看置顶'),
              trailing: Switch(
                value: draft.pinnedOnly,
                onChanged: (v) => _update(draft.copyWith(pinnedOnly: v)),
              ),
              onTap: () => _update(draft.copyWith(pinnedOnly: !draft.pinnedOnly)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _update(const TimelineFilter()),
                      child: const Text('重置筛选'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        ref.read(timelineFilterProvider.notifier).state = draft;
                        // 换了筛选条件就回到首屏条数：否则会带着续拉出来的大 limit
                        // 在新条件上重查一次，白拉几十条
                        ref.read(timelineLimitProvider.notifier).state =
                            kTimelinePageSize;
                        Navigator.pop(context);
                      },
                      child: const Text('查看结果'),
                    ),
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

/// 心情 1–5 档色点（Material 色板映射，避免自定义色过多）
const _moodColors = <int, Color>{
  1: Color(0xFF90CAF9),
  2: Color(0xFFA5D6A7),
  3: Color(0xFFFFF59D),
  4: Color(0xFFFFCC80),
  5: Color(0xFFEF9A9A),
};

/// 列表行模型：月头 / 日头 / 卡片，摊平成一维再交给 builder
/// （比嵌套 for 更好控制 itemCount，也让分组逻辑留在可测的纯函数里）
sealed class _Row {}

class _MonthRow extends _Row {
  _MonthRow(this.label, this.count, this.pinned);

  final String label;
  final int count;
  final bool pinned;
}

class _DayRow extends _Row {
  _DayRow(this.label);

  final String label;
}

class _EntryRow extends _Row {
  _EntryRow(this.entry);

  final TimelineEntry entry;
}

List<_Row> _flatten(List<EntryMonthGroup> groups) {
  final rows = <_Row>[];
  for (final g in groups) {
    rows.add(_MonthRow(g.label, g.count, g.pinned));
    for (final d in g.days) {
      rows.add(_DayRow(d.label));
      rows.addAll(d.items.map(_EntryRow.new));
    }
  }
  return rows;
}

/// 续拉触发距离：距列表底部不足 400px 就开始取下一页
const double _kLoadMoreThreshold = 400;

/// 列表（W11）：下拉刷新 + 滚动续拉 + 底部一行轻量提示
class _TimelineList extends ConsumerWidget {
  const _TimelineList({
    required this.entries,
    this.root,
    required this.loading,
  });

  final List<TimelineEntry> entries;

  /// App 支持目录（相对路径的解析基准）；为 null 表示尚未取到
  final String? root;

  /// 是否正在加载（首屏流还没到 / 正在续拉）
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limit = ref.watch(timelineLimitProvider);
    // 「还有更多」判定：本次结果长度 >= 当前 limit 即视为可能还有。
    // 不为此多查一次 count——分页本身就是为了省查询，多花一次 IO 就本末倒置了。
    final hasMore = entries.length >= limit;
    final rows = _flatten(groupByMonth(entries));

    return RefreshIndicator(
      onRefresh: () => _onRefresh(ref),
      child: NotificationListener<ScrollNotification>(
        // 返回 false：让通知继续向上冒泡，RefreshIndicator 才收得到滑动手势
        onNotification: (notification) {
          if (notification.metrics.extentAfter < _kLoadMoreThreshold) {
            _loadMore(ref);
          }
          return false;
        },
        child: ListView.builder(
          // 数据不足一屏时也要能拉出刷新指示器
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 4, bottom: 96),
          // 预渲染视口外的缓冲：滑动时提前备好下一屏，减少"边滑边建"的抖动
          scrollCacheExtent: const ScrollCacheExtent.viewport(1.0),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == rows.length) {
              return _ListFooter(
                // 续拉期间 hasMore 会因为 limit 已上调而短暂为 false，
                // 所以「正在加载」要单独看 loading，别在这一瞬间闪出「已经到底了」
                text: loading || hasMore ? '正在加载…' : '已经到底了',
              );
            }
            final row = rows[i];
            return switch (row) {
              _MonthRow() => _MonthHeader(row: row),
              _DayRow() => _DayHeader(row: row),
              _EntryRow() => _EntryCard(row.entry, root: root),
            };
          },
        ),
      ),
    );
  }

  /// 续拉一页：把 limit 加一页，流自动带着新 limit 重查
  void _loadMore(WidgetRef ref) {
    final state = ref.read(timelineStreamProvider);
    // 上一页还没回来就不再叠加，否则一次滑动会把 limit 连加好几页
    if (state.isLoading) return;
    final limit = ref.read(timelineLimitProvider);
    final current = state.valueOrNull;
    if (current == null || current.length < limit) return;
    ref.read(timelineLimitProvider.notifier).state = limit + kTimelinePageSize;
  }

  /// 下拉刷新：先复位条数再 invalidate，否则刷新后仍按续拉后的大 limit 重查
  Future<void> _onRefresh(WidgetRef ref) async {
    ref.read(timelineLimitProvider.notifier).state = kTimelinePageSize;
    ref.invalidate(timelineStreamProvider);
    try {
      // 等第一帧到达再收起指示器：立刻返回会让刷新动画一闪而过，看着像没刷新
      await ref.read(timelineStreamProvider.future);
    } on Object {
      // 刷新失败时不拦着指示器收起，错误交给页面错误态呈现
    }
  }
}

/// 列表底部提示：一行小字，不转圈
class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.row});

  final _MonthRow row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Row(
        children: [
          Icon(row.pinned ? Icons.push_pin : Icons.calendar_today_outlined,
              size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            row.label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 6),
          Text(
            '${row.count} 条',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.row});

  final _DayRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
      child: Text(
        row.label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: Theme.of(context).hintColor),
      ),
    );
  }
}

/// 列表缩略图（W6 性能改造，W7 沿用）
/// 三处关键点，缺一个都会让滑动掉帧：
/// 1. **优先用 thumb 而不是原图**：52dp 的框里解码 4000×3000 的原图，
///    单张就吃掉几十 MB 解码内存，是列表卡顿的头号来源；
/// 2. **cacheWidth 限制解码尺寸**：即使回退到原图，也只按显示尺寸×DPR 解码；
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
      cacheWidth: (size * dpr).round(),
      // W10：此前失败态是「空白色块」——用户看到卡片左上空一块，
      // 既不知道那是图片，也不知道它为什么空。给出破图图标，至少是可归因的状态。
      errorBuilder: (_, _, _) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EntryCard extends ConsumerWidget {
  const _EntryCard(this.entry, {this.root});

  final TimelineEntry entry;

  /// App 支持目录（null 时图片位显示占位色块，不发起异步）
  final String? root;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moodColor = entry.mood == null ? null : _moodColors[entry.mood!];
    // 有缩略图用缩略图，没有（W4 期历史数据）回退原图，但解码尺寸仍受限
    final thumbRel = entry.firstAssetThumbPath ?? entry.firstAssetRelPath;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/detail?id=${entry.id}'),
        // 长按出操作菜单：置顶 / 删除（W7 置顶收藏）
        onLongPress: () => _showEntryMenu(context, ref, entry),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: thumbRel != null
                    // Hero：卡片缩略图飞向详情页大图，形成连续的空间感（W10）
                    ? Hero(
                        tag: entryThumbHeroTag(entry.id),
                        child: _ThumbTile(rel: thumbRel, root: root, size: 52),
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
                        if (entry.pinned) ...[
                          Icon(Icons.push_pin,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 4),
                        ],
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

  Future<void> _showEntryMenu(
      BuildContext context, WidgetRef ref, TimelineEntry entry) async {
    final actions = ref.read(timelineActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(entry.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(entry.pinned ? '取消置顶' : '置顶这条'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final pinned = await actions.togglePinned(entry);
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text(pinned ? '已置顶' : '已取消置顶')),
                  );
                } on Exception catch (error) {
                  if (!context.mounted) return;
                  messenger.showSnackBar(SnackBar(content: Text('操作失败：$error')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('移到回收站'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await actions.softDelete(entry.id);
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('已移到回收站'),
                      action: SnackBarAction(
                        label: '撤销',
                        onPressed: () => actions.restore(entry.id),
                      ),
                    ),
                  );
                } on Exception catch (error) {
                  if (!context.mounted) return;
                  messenger.showSnackBar(SnackBar(content: Text('删除失败：$error')));
                }
              },
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

/// 时间轴空态（W8）：区分两种"空"——库里本就没有记录 vs 筛选后无结果。
///
/// 主代理后续会把这里替换成共享的 EmptyState 组件，故保持内联、简单，
/// 但必须可直接用：库空给欢迎引导（主行动去写第一条），筛选空明确归因到筛选
/// 并提供一键清除（直接重置 timelineFilterProvider，不依赖客户端过滤）。
/// 空态（W8）：统一走共享组件 [EmptyState]，但**必须区分两种成因**——
/// ① 库里原本就没有任何记录 → 欢迎式引导；② 有筛选条件但筛完为空 →
/// 明确告知是筛选导致并给一键清除。两者混为一谈会让用户误以为数据丢了。
Widget _buildEmptyState(BuildContext context, WidgetRef ref, bool noFilter) {
  if (noFilter) {
    // 真·空库：主行动是去写第一条记录
    return EmptyState(
      icon: Icons.spa_outlined,
      title: '还没有记录',
      subtitle: '点右下角「记一笔」，写下你的第一条',
      actionLabel: '记一笔',
      onAction: () => context.push('/editor'),
    );
  }

  // 有筛选但筛空：清除筛选就是把这个 StateProvider 重置为默认值，
  // watchTimeline 的流会带着新的 where 自动重查。
  return EmptyState(
    icon: Icons.filter_alt_off_outlined,
    title: '没有符合条件的记录',
    subtitle: '当前的筛选条件没有匹配到任何记录',
    actionLabel: '清除筛选',
    onAction: () => ref.read(timelineFilterProvider.notifier).state =
        const TimelineFilter(),
  );
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
