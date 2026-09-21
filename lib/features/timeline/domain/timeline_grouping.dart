import 'entities/timeline_entry.dart';

/// 时间轴分组（W7 月分组）
///
/// 纯 Dart、无 Flutter/Drift 依赖——分组是列表渲染里最容易写错又最该被单测的
/// 一段逻辑（跨月、跨年、置顶插入都要对），所以独立成可测的纯函数。
///
/// 结构：月 → 日 → 条目；置顶项单独成一组排在最前。
class EntryDayGroup {
  EntryDayGroup(this.label);

  /// 形如「09月21日 周一」
  final String label;
  final List<TimelineEntry> items = [];
}

class EntryMonthGroup {
  EntryMonthGroup(this.label, {this.pinned = false});

  /// 形如「2026年09月」；置顶组为「置顶」
  final String label;

  /// 该组是否为置顶组（置顶组不计月份语义）
  final bool pinned;
  final List<EntryDayGroup> days = [];

  /// 组内条目数（月头部展示「N 条」）
  int get count => days.fold(0, (sum, d) => sum + d.items.length);
}

const _weekdayNames = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String _monthLabel(DateTime d) =>
    '${d.year}年${d.month.toString().padLeft(2, '0')}月';

String _dayLabel(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}月${d.day.toString().padLeft(2, '0')}日'
    ' ${_weekdayNames[d.weekday - 1]}';

/// 把已按「置顶优先 + 日期倒序」排好的条目切成月分组。
///
/// 约定（与 DAO `watchTimeline` 的 orderBy 对齐）：
/// - 入参顺序即展示顺序，函数只做切分、不再排序；
/// - 置顶项抽出来放第一组，避免「置顶优先」被月份切碎；
/// - 同月同日合并为一个日锚点。
List<EntryMonthGroup> groupByMonth(List<TimelineEntry> entries) {
  final groups = <EntryMonthGroup>[];

  final pinned = entries.where((e) => e.pinned).toList(growable: false);
  if (pinned.isNotEmpty) {
    groups.add(EntryMonthGroup('置顶', pinned: true)..days.addAll(_daysOf(pinned)));
  }

  final rest = entries.where((e) => !e.pinned);
  EntryMonthGroup? currentMonth;
  for (final e in rest) {
    final label = _monthLabel(e.entryDate);
    if (currentMonth == null || currentMonth.label != label) {
      currentMonth = EntryMonthGroup(label);
      groups.add(currentMonth);
    }
    final dayLabel = _dayLabel(e.entryDate);
    if (currentMonth.days.isEmpty || currentMonth.days.last.label != dayLabel) {
      currentMonth.days.add(EntryDayGroup(dayLabel));
    }
    currentMonth.days.last.items.add(e);
  }
  return groups;
}

List<EntryDayGroup> _daysOf(List<TimelineEntry> items) {
  final days = <EntryDayGroup>[];
  for (final e in items) {
    final label = _dayLabel(e.entryDate);
    if (days.isEmpty || days.last.label != label) {
      days.add(EntryDayGroup(label));
    }
    days.last.items.add(e);
  }
  return days;
}
