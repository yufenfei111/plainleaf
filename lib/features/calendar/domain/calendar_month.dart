// 日历网格的纯计算（W12）
//
// 为什么把这几段抽成纯函数：日期边界（月初/月末、跨月、跨年、闰年）是
// 最容易写错又最该被单测钉死的一段逻辑，一旦混进 Widget 里就只能靠肉眼验证。
// 这里全部不依赖 Flutter / Drift，可以用 `test()` 直接喂日期断言。
//
// 网格约定：**周一为一周首日**（与国内日历习惯一致），月初前与月末后的
// 空位用 `null` 占位，长度恒为 7 的整数倍，调用方按 7 个一排行铺即可。
//
// 用 `//` 而不是 `///`：顶层 `///` 后面不跟声明会被 CI 判
// dangling_library_doc_comments（--fatal-infos 口径下算失败）。

/// 归一化到「当天零点」。
///
/// 数据库里的 entryDate 带时分秒，直接拿 DateTime 做 Map key 会因为时间不同
/// 而被当成两天；先降到「日」这一粒度，聚合与相等判断才稳定。
DateTime dayKey(DateTime value) => DateTime(value.year, value.month, value.day);

/// 归一化到「当月 1 号」：月份选择器与流查询都以它为准，便于 `==` 比较。
DateTime monthStart(DateTime value) => DateTime(value.year, value.month);

/// 下个月 1 号（用 `month + 1` 让 Dart 自己处理 12 → 次年 1 月的进位）。
DateTime nextMonthStart(DateTime value) => DateTime(value.year, value.month + 1);

/// 上个月 1 号（用 `month - 1` 让 Dart 自己处理 1 → 上年 12 月的退位）。
DateTime previousMonthStart(DateTime value) => DateTime(value.year, value.month - 1);

/// 是否同一天（只比年月日，忽略时分秒）。
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// `day` 是否严格晚于 `today` 所在的那一天。
///
/// 用「日」粒度比较，所以今天一整天的任意时刻都不算未来——否则用户上午看到
/// 今天的格子是灰的，下午又亮了，属于自相矛盾的交互。
bool isFutureDay(DateTime day, DateTime today) =>
    dayKey(day).isAfter(dayKey(today));

/// 当月有多少天。
///
/// 取「下月 0 号」这个技巧让 Dart 直接返回上月最后一天：
/// 闰年 2 月会得到 29，不必自己写 `% 4` 那套（写错概率更高）。
int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// 生成某月的日历网格单元（长度恒为 7 的整数倍）。
///
/// 前补位个数 = 1 号是周几往前数到周一；后补位把最后一行填满。
/// 补位与「当月之外的日期」都返回 null，渲染时留空即可。
List<DateTime?> monthGridCells(DateTime month) {
  final first = monthStart(month);
  final leading = first.weekday - 1; // DateTime 周一=1；减 1 得前补位数
  final total = leading + daysInMonth(first);
  final trailing = (7 - total % 7) % 7;
  return <DateTime?>[
    for (var i = 0; i < leading; i++) null,
    for (var day = 1; day <= daysInMonth(first); day++)
      DateTime(first.year, first.month, day),
    for (var i = 0; i < trailing; i++) null,
  ];
}

/// 把一串日期聚合成「每天几条」。
///
/// 项目惯例（与 DAO `watchEntryDates` 的注释一致）：能在 Dart 层聚合就不写
/// SQLite 日期函数——那些函数在不同 engine 上可用性不一致，写错要等运行时才炸；
/// 一个月的量级下这层聚合是常数级开销。
Map<DateTime, int> aggregateDailyCounts(Iterable<DateTime> dates) {
  final counts = <DateTime, int>{};
  for (final date in dates) {
    final key = dayKey(date);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

/// 密度分级：0 = 无记录，1 / 2 / 3 三档（3 档封顶）。
///
/// 封顶在 3 是因为人眼对背景深浅的区分就三档左右，再细分只会让深浅难辨；
/// 一天写 10 条与 3 条看起来一样，是刻意的取舍而不是缺陷。
int densityLevel(int count) {
  if (count <= 0) return 0;
  if (count >= 3) return 3;
  return count;
}

/// 「2026年09月」这类月份标题。
String monthLabel(DateTime month) =>
    '${month.year}年${month.month.toString().padLeft(2, '0')}月';

/// 星期表头（周一 → 周日），与 [monthGridCells] 的列顺序严格对应。
const List<String> weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
