import 'dart:async';
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
import 'widgets/on_this_day_card.dart';

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
            // W12：日历回顾入口。放在时间轴而不是新开 Tab ——
            // 「按天回看」是时间轴的另一种视图，不是并列的一级目的地。
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: '日历回顾',
            onPressed: () => context.push('/calendar'),
          ),
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
        // 与 home_page「我的」Tab 的 FAB 区分开（见那边的注释）：
        // 同一条 PageRoute 子树里不允许两个 Hero 共用 tag。
        heroTag: 'timeline-compose',
        onPressed: () => context.push('/editor'),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      body: Column(
        children: [
          const _FilterBar(),
          // 那年今日（W12）：无数据时自身塌成 0 尺寸，不留白占位。
          // 挂在列表之外而没插进列表首项：列表那层有稳定 key + 入场动画的
          // 集合差集判断，插一项会牵动它的下标与「谁是新插入」的判定，
          // 收益（随滚隐藏）抵不上风险。
          const OnThisDayCard(),
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
///
/// 每行带一个**跨流重发稳定**的 [rowKey]：列表按 key 复用行 State，
/// 只有真正新出现的行才会播入场动画（详见 [_EntryCard]）。
sealed class _Row {
  const _Row(this.rowKey);

  final Key rowKey;
}

class _MonthRow extends _Row {
  _MonthRow(this.label, this.count, this.pinned)
      : super(ValueKey('month-$pinned-$label'));

  final String label;
  final int count;
  final bool pinned;
}

class _DayRow extends _Row {
  // 日头标签会跨组重名（置顶组与月份组都可能是「09月21日 周一」），
  // 故用所属月组标签做作用域，保证 key 在整列内唯一、不会串行。
  _DayRow(this.label, {required String scope})
      : super(ValueKey('day-$scope-$label'));

  final String label;
}

class _EntryRow extends _Row {
  _EntryRow(this.entry) : super(ValueKey('entry-${entry.id}'));

  final TimelineEntry entry;
}

List<_Row> _flatten(List<EntryMonthGroup> groups) {
  final rows = <_Row>[];
  for (final g in groups) {
    rows.add(_MonthRow(g.label, g.count, g.pinned));
    for (final d in g.days) {
      rows.add(_DayRow(d.label, scope: g.label));
      rows.addAll(d.items.map(_EntryRow.new));
    }
  }
  return rows;
}

/// 行增删过渡时长：克制在 180ms（红线 ≤250ms，且必须一次性、无循环）。
const Duration _kRowAnimDuration = Duration(milliseconds: 180);

/// 行入场/退场本体：淡入淡出 + 高度展开/收起，同为 180ms 一次性。
///
/// 为什么退场要带高度收起：删除时若只做淡出，卡片仍占着原高度，等流数据回来把它
/// 摘掉的那一帧，下方所有行会「啪」地整体上跳一个卡片高——淡出反而把这一跳衬得更
/// 明显。让高度同步收到 0，摘除时高度本就是 0，衔接是连续的。收起取顶部对齐，
/// 行像是「往上收走」而不是原地压扁。
class _RowTransition extends StatelessWidget {
  const _RowTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SizeTransition(
        sizeFactor: animation,
        // Flutter 3.41 起 axisAlignment 被弃用（CI 是 --fatal-infos 口径，
        // 弃用告警也算失败）。纵向展开的 -1 等价于顶部对齐。
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

/// 续拉触发距离：距列表底部不足 400px 就开始取下一页
const double _kLoadMoreThreshold = 400;

/// 列表（W11）：下拉刷新 + 滚动续拉 + 底部一行轻量提示
///
/// W12 起额外负责「哪些条目是这次新插入的」：以条目 id 集合的前后差集判定。
/// 为什么不自己比对整份扁平行列表（AnimatedList 那套）：行里还混着月头/日头，
/// 一条记录增删会牵动多行下标，手算这种差分既易错又容易和 W11 的续拉/滚动位置打架。
/// id 集合差集只回答「这条是不是新来的」，不碰任何下标，安全得多。
class _TimelineList extends ConsumerStatefulWidget {
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
  ConsumerState<_TimelineList> createState() => _TimelineListState();
}

class _TimelineListState extends ConsumerState<_TimelineList> {
  /// 上一次见过的条目 id
  late final Set<int> _knownIds;

  /// 本次结果里新出现的条目 id：只有它们播入场动画
  Set<int> _enteringIds = const {};

  @override
  void initState() {
    super.initState();
    // 首屏整体灌入不算「新插入」：否则冷启动会整列一起做动画，
    // 而且首帧所有行从 0 高开始会让 ListView 误判视口、把全部卡片（含图片）一次建出来
    _knownIds = widget.entries.map((e) => e.id).toSet();
  }

  @override
  void didUpdateWidget(covariant _TimelineList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.entries.map((e) => e.id).toSet();
    _enteringIds = current.difference(_knownIds);
    _knownIds
      ..clear()
      ..addAll(current);
  }

  @override
  Widget build(BuildContext context) {
    final limit = ref.watch(timelineLimitProvider);
    // 「还有更多」判定：本次结果长度 >= 当前 limit 即视为可能还有。
    // 不为此多查一次 count——分页本身就是为了省查询，多花一次 IO 就本末倒置了。
    final hasMore = widget.entries.length >= limit;
    final rows = _flatten(groupByMonth(widget.entries));
    // key → 当前下标。给 ListView 的 findChildIndexCallback 用：插入/删除会让后续行
    // 下标平移，有了它 sliver 仍能按 key 找回原 element、复用 State。
    final indexByKey = <Key, int>{
      for (var i = 0; i < rows.length; i++) rows[i].rowKey: i,
    };

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: NotificationListener<ScrollNotification>(
        // 返回 false：让通知继续向上冒泡，RefreshIndicator 才收得到滑动手势
        onNotification: (notification) {
          if (notification.metrics.extentAfter < _kLoadMoreThreshold) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          // 数据不足一屏时也要能拉出刷新指示器
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 4, bottom: 96),
          // 预渲染视口外的缓冲：滑动时提前备好下一屏，减少"边滑边建"的抖动
          scrollCacheExtent: const ScrollCacheExtent.viewport(1.0),
          findChildIndexCallback: (key) => indexByKey[key],
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == rows.length) {
              return _ListFooter(
                // 续拉期间 hasMore 会因为 limit 已上调而短暂为 false，
                // 所以「正在加载」要单独看 loading，别在这一瞬间闪出「已经到底了」
                text: widget.loading || hasMore ? '正在加载…' : '已经到底了',
              );
            }
            final row = rows[i];
            return switch (row) {
              // 月头/日头只是分组装饰，出现/消失不做动画（否则加一条会连带动一片）
              _MonthRow() => _MonthHeader(key: row.rowKey, row: row),
              _DayRow() => _DayHeader(key: row.rowKey, row: row),
              _EntryRow() => _EntryCard(
                  row.entry,
                  key: row.rowKey,
                  root: widget.root,
                  entering: _enteringIds.contains(row.entry.id),
                ),
            };
          },
        ),
      ),
    );
  }

  /// 续拉一页：把 limit 加一页，流自动带着新 limit 重查
  void _loadMore() {
    final state = ref.read(timelineStreamProvider);
    // 上一页还没回来就不再叠加，否则一次滑动会把 limit 连加好几页
    if (state.isLoading) return;
    final limit = ref.read(timelineLimitProvider);
    final current = state.valueOrNull;
    if (current == null || current.length < limit) return;
    ref.read(timelineLimitProvider.notifier).state = limit + kTimelinePageSize;
  }

  /// 下拉刷新：先复位条数再 invalidate，否则刷新后仍按续拉后的大 limit 重查
  Future<void> _onRefresh() async {
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
  const _MonthHeader({super.key, required this.row});

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
  const _DayHeader({super.key, required this.row});

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

class _EntryCard extends ConsumerStatefulWidget {
  const _EntryCard(this.entry, {super.key, this.root, required this.entering});

  final TimelineEntry entry;

  /// App 支持目录（null 时图片位显示占位色块，不发起异步）
  final String? root;

  /// 本次流更新里这条记录是否为新插入（决定是否播入场动画）
  final bool entering;

  @override
  ConsumerState<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends ConsumerState<_EntryCard>
    with SingleTickerProviderStateMixin {
  /// 0 = 收起/透明，1 = 展开/不透明。入场从 0 播到 1，删除时反播做退场。
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _kRowAnimDuration,
  );

  late final Animation<double> _curve =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // 只有「这次新插入」的那条才播入场；滚动重建、筛选重发、下拉刷新拿到的旧行
    // 直接落到终态——否则来回滚动一遍，划回来就会看见整屏卡片又闪一次。
    if (widget.entering) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _RowTransition(animation: _curve, child: _buildCard(context));

  /// 卡片本体单独拆出来：动画外壳套在最外层，卡片内部结构保持原样，
  /// 免得为了包一层过渡把整段布局重排缩进。
  Widget _buildCard(BuildContext context) {
    final entry = widget.entry;
    final moodColor = entry.mood == null ? null : _moodColors[entry.mood!];
    // 有缩略图用缩略图，没有（W4 期历史数据）回退原图，但解码尺寸仍受限
    final thumbRel = entry.firstAssetThumbPath ?? entry.firstAssetRelPath;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/detail?id=${entry.id}'),
        // 长按出操作菜单：置顶 / 删除（W7 置顶收藏）
        onLongPress: () => _showEntryMenu(context),
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
                        child: _ThumbTile(
                            rel: thumbRel, root: widget.root, size: 52),
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

  Future<void> _showEntryMenu(BuildContext context) async {
    final entry = widget.entry;
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
              onTap: () {
                Navigator.pop(context);
                // 先播退场再落库（见 _deleteWithExit）。这里不 await：
                // 弹层自身的关闭不该和卡片动画的时序绑在一起。
                unawaited(_deleteWithExit());
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 删除：先播 180ms 退场，再落库。
  ///
  /// 为什么不 `await _ctrl.reverse()`：TickerFuture 在卡片被上游流回收（dispose）时
  /// 不会完成，await 会永久挂起。这里改用固定短延时的时序，落库是否执行与动画壳的
  /// 存活无关。
  Future<void> _deleteWithExit() async {
    final entry = widget.entry;
    final actions = ref.read(timelineActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    unawaited(_ctrl.reverse());
    await Future<void>.delayed(_kRowAnimDuration);
    try {
      await actions.softDelete(entry.id);
      if (!mounted) return;
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
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('删除失败：$error')));
      // 删除失败要把卡片淡回来，不能把它留在半透明的「已退场」状态
      _ctrl.forward();
    }
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
