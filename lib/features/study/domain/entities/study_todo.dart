/// 学习待办领域实体（纯 Dart）
class StudyTodo {
  const StudyTodo({
    required this.id,
    required this.content,
    required this.done,
    required this.createdAt,
    this.completedAt,
    this.dueDate,
    this.priority = 0,
  });

  final int id;
  final String content;
  final bool done;

  /// 完成时间（§4.3 修正：学习统计「每日完成数」依赖）
  final DateTime? completedAt;
  final DateTime? dueDate;
  final int priority;

  /// 创建时间（W11）：录入完成后新条目要排在同级的最上面，
  /// 「写完抬头就看见自己那条」比任何排序话术都直观。
  final DateTime createdAt;
}