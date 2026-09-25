import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../../app/providers.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../domain/calendar_month.dart';
import '../../domain/entities/calendar_entry.dart';
import '../providers/calendar_providers.dart';

/// 日历回顾页（W12）
///
/// 设计取舍：
/// - 一屏只有「月网格」一个主体，点某天用底部弹层看当天记录——把弹层做成次级区域
///   而不是常驻列表，日历本身才不会被挤成一条窄带；
/// - 密度只分 3 档同一强调色的深浅，不做热力柱状图之类需要图表库的东西
///   （红线：不新增第三方依赖）；
/// - 未来的日期与没写的日期都弱化，且不可点——点了没反应的空格子最伤手感。
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日历'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: '回到本月',
            onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                monthStart(DateTime.now()),
          ),
        ],
      ),
      body: Column(
        children: [
          const _MonthHeader(),
          const _WeekdayHeader(),
          Expanded(child: _MonthBody(month: month)),
        ],
      ),
    );
  }
}

/// 月份切换条：左右箭头 + 居中月份标题。
///
/// 左右箭头用的是 IconButton（默认 48dp 命中区），满足触控 ≥44dp 的红线。
class _MonthHeader extends ConsumerWidget {
  const _MonthHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '上个月',
            onPressed: () =>
                ref.read(selectedMonthProvider.notifier).state =
                    previousMonthStart(month),
          ),
          Expanded(
            child: Center(
              child: Text(
                monthLabel(month),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '下个月',
            onPressed: () =>
                ref.read(selectedMonthProvider.notifier).state =
                    nextMonthStart(month),
          ),
        ],
      ),
    );
  }
}

/// 星期表头：顺序必须与 [monthGridCells] 的列一一对应（周一 → 周日）。
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          for (final label in weekdayLabels)
            Expanded(
              child: Center(child: Text(label, style: style)),
            ),
        ],
      ),
    );
  }
}

/// 月网格的三态分发（loading 骨架 / error 重试 / data 网格）。
class _MonthBody extends ConsumerWidget {
  const _MonthBody({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hits = ref.watch(monthDateHitsProvider);
    return hits.when(
      // 骨架也按 7 列铺，让加载态与真实网格形状一致，数据回来时不会整屏跳变
      loading: () => const GridSkeleton(crossAxisCount: 7),
      error: (error, _) => _ErrorView(
        error: '$error',
        onRetry: () => ref.invalidate(monthDateHitsProvider),
      ),
      data: (list) => _MonthGrid(
        month: month,
        counts: aggregateDailyCounts(list.map((hit) => hit.date)),
        today: DateTime.now(),
      ),
    );
  }
}

/// 月网格：按周铺行。
///
/// 为什么自己用 Column + Row 而不是 GridView：
/// 日历的行数固定（4–6 行）、每格要保证触控高度，手铺能精确控制格子尺寸，
/// 也免去 GridView 在 Column 里 shrinkWrap 带来的二次布局开销。
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.counts,
    required this.today,
  });

  final DateTime month;
  final Map<DateTime, int> counts;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final cells = monthGridCells(month);
    final weeks = cells.length ~/ 7;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        // 触控红线 ≥44dp：宽度一般来自屏宽；高度取「宽度」但不低于 44、不高于 60，
        // 免得大屏上格子被拉成难看的方块。极端小屏若总高溢出，外层可滚动兜底。
        final cellHeight = math.max(44.0, math.min(cellWidth, 60.0));
        return SingleChildScrollView(
          child: Column(
            children: [
              for (var week = 0; week < weeks; week++)
                SizedBox(
                  height: cellHeight,
                  child: Row(
                    children: [
                      for (var col = 0; col < 7; col++)
                        SizedBox(
                          // 宽高都给死：命中区才会铺满整格（≈51×51），
                          // 否则 InkWell 只会缩到中间那个 36dp 小圆上，够不到 44dp 红线。
                          width: cellWidth,
                          height: cellHeight,
                          child: _cellFor(context, cells[week * 7 + col]),
                        ),
                    ],
                  ),
                ),
              if (counts.isEmpty) const _EmptyMonthHint(),
            ],
          ),
        );
      },
    );
  }

  Widget _cellFor(BuildContext context, DateTime? day) {
    if (day == null) return const SizedBox.shrink();
    final key = dayKey(day);
    final count = counts[key] ?? 0;
    final future = isFutureDay(day, today);
    return _DayCell(
      day: day,
      count: count,
      isToday: isSameDay(day, today),
      isFuture: future,
      // 没记录或还没到的那天不挂 onTap：点了没反馈比点了弹个空更让人困惑
      onTap: (count == 0 || future) ? null : () => _openDaySheet(context, day),
    );
  }
}

/// 单日格子：背景深浅 = 当天记录数（0/1/2/3+ 四态，1–3 为强调色三档）。
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.count,
    required this.isToday,
    required this.isFuture,
    this.onTap,
  });

  final DateTime day;
  final int count;
  final bool isToday;
  final bool isFuture;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final level = densityLevel(count);

    Color? fill;
    var textColor = count > 0 ? cs.onSurface : cs.onSurfaceVariant;
    if (level == 1) {
      fill = cs.primary.withAlpha(30);
    } else if (level == 2) {
      fill = cs.primary.withAlpha(80);
    } else if (level == 3) {
      // 最深一档直接用实心 primary，配 onPrimary 保证深浅色模式都有对比度
      fill = cs.primary;
      textColor = cs.onPrimary;
    }
    if (isFuture) textColor = cs.onSurfaceVariant.withAlpha(120);

    return Semantics(
      button: onTap != null,
      label: '${day.day}日，$count 条记录',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        // 命中区撑满整格（宽度≈一列、高度≥44dp），而不是只包住那个小圆
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: isToday ? Border.all(color: cs.primary, width: 1.5) : null,
            ),
            child: Text(
              '${day.day}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: level > 0 ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 整月无记录时的一行提示：网格本身仍在（日历不该被空态顶掉），只补一句归因。
class _EmptyMonthHint extends StatelessWidget {
  const _EmptyMonthHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        '本月还没有记录',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// 打开某天的记录弹层。
Future<void> _openDaySheet(BuildContext context, DateTime day) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // 记录多时要能滚动，弹层允许超过半屏
    isScrollControlled: true,
    builder: (_) => _DaySheet(day: day),
  );
}

/// 某天记录弹层：标题一行 + 记录列表（加载态用文字，不用转圈动画）。
class _DaySheet extends ConsumerWidget {
  const _DaySheet({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(dayEntriesProvider(day));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '${day.month}月${day.day}日',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: entries.when(
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: Text('这一天没有记录')),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: list.length,
                        itemBuilder: (context, i) =>
                            _DayEntryTile(entry: list[i]),
                      ),
                // 同一天的详情是几次本地查询，通常几毫秒；用一行文字占位即可，
                // 不引入 CircularProgressIndicator——循环动画是被明令禁止的
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('正在读取…')),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 32, horizontal: 24),
                  child: Center(child: Text('加载失败：$error')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹层里的一条记录：缩略图（有则显示）+ 标题 + 摘录，点进详情。
class _DayEntryTile extends ConsumerWidget {
  const _DayEntryTile({required this.entry});

  final CalendarEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final root = ref.watch(supportDirProvider).valueOrNull;
    final rel = entry.thumbRelPath;
    // 先拼成绝对路径再判空：三元里直接写 p.join 依赖空安全提升，
    // 落成一个局部变量后逻辑与静态分析都更直白。
    final String? absPath =
        (rel != null && root != null) ? p.join(root, rel) : null;

    return ListTile(
      leading: SizedBox(
        width: 44,
        height: 44,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: absPath != null
              ? Image.file(
                  File(absPath),
                  fit: BoxFit.cover,
                  // 列表缩略图必须限解码尺寸，否则一张原图就能吃掉几十 MB
                  cacheWidth:
                      (44 * MediaQuery.devicePixelRatioOf(context)).round(),
                  errorBuilder: (_, _, _) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : Container(
                  color: cs.primaryContainer,
                  child: Icon(Icons.article_outlined, color: cs.primary),
                ),
        ),
      ),
      title: Text(
        entry.title.isEmpty ? '(无标题)' : entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: entry.snippet.isEmpty
          ? null
          : Text(
              entry.snippet,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        // 先握住 router 再关弹层：关掉后当前 context 所挂的弹层已在下线中，
        // 跨过 pop 再取 GoRouter.of(context) 是不安全的。
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.push('/detail?id=${entry.id}');
      },
    );
  }
}

/// 网格加载失败态：说明成因 + 原地重试入口。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text('日历加载失败', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
