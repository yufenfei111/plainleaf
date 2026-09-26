import 'entities/study_todo.dart';

/// 某一天的完成概况（W12「每日完成数」）
///
/// 纯数据 + 两个派生量，UI 只负责把数字画出来，不在这里掺任何格式。
class DailyStats {
  const DailyStats({required this.total, required this.done});

  /// 这一天的任务盘子总数（未完成存量 + 当天完成的）
  final int total;

  /// 当天完成的数量
  final int done;

  /// 完成率 0.0 ~ 1.0
  ///
  /// 盘子为空时给 0 而不是 NaN：进度条拿到 NaN 会整条消失，
  /// 「今天还没有任务」不该表现得像渲染崩了。
  double get ratio => total == 0 ? 0.0 : done / total;

  /// 展示用的整数百分比（向下取整：99.6% 不该显示成 100%，否则看着像做完了）
  int get percent => (ratio * 100).floor();

  /// 空盘子（流还没到 / 出错时的降级值）
  static const empty = DailyStats(total: 0, done: 0);
}

/// 统计 [day] 当天的完成情况（纯函数，跨天边界靠单测锁住）
///
/// 归属规则写在这里，UI 不重复判断：
/// - **未完成**：一律计入 [day] 的盘子。昨天遗留的待办今天依然压在头上，
///   若按创建日归属，第二天打开就会看到「共 0」而列表里明明还躺着几条，
///   这一下最像程序坏了。
/// - **已完成**：只在完成当天计入，[StudyTodo.completedAt] 缺失时退回创建日，
///   让每条待办都有唯一归属日——不会凭空消失，也不会重复计数。
///
/// [day] 只取年月日：传入带时分秒的时间戳也会正确归一到当天，
/// 因此「23:59 完成」和「00:01 完成」只要同一天就算同一天。
DailyStats dailyCompletion(List<StudyTodo> todos, DateTime day) {
  var total = 0;
  var done = 0;
  for (final todo in todos) {
    if (!todo.done) {
      total++;
      continue;
    }
    if (_isSameDay(todo.completedAt ?? todo.createdAt, day)) {
      total++;
      done++;
    }
  }
  return DailyStats(total: total, done: done);
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
