/// 日历「某一天」列表里的一条记录（纯 Dart，不依赖 Drift / Flutter）
///
/// 为什么不直接复用时间轴的 TimelineEntry：日历只关心「标题 + 摘录 + 缩略图」
/// 这几样，把整个领域实体端上来会让日历 feature 反向依赖时间轴 feature 的
/// 类型定义；这里用最小字段集切一刀，两边各自演化互不牵动。
class CalendarEntry {
  const CalendarEntry({
    required this.id,
    required this.date,
    this.title = '',
    this.snippet = '',
    this.thumbRelPath,
  });

  /// entries 主键（点进 `/detail?id=` 用）
  final int id;

  /// 记录日期（带时分秒，展示时可只用时分）
  final DateTime date;

  /// 标题；为空时由 UI 统一显示「(无标题)」
  final String title;

  /// 正文纯文本摘录
  final String snippet;

  /// 首图相对路径（thumb 优先、回退原图）；无图或有图但支持目录未就绪时为 null
  final String? thumbRelPath;
}
