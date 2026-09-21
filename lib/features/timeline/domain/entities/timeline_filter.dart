import 'timeline_entry.dart';

/// 时间轴筛选条件（W7 组织能力）
///
/// 放在 domain 层、保持不可变：UI 持有它、Repository 翻译成 SQL where，
/// 数据层不反向依赖 Flutter。三个维度与 §三 W7 验收一致：
/// 笔记本 / 类型 / 仅看置顶。
class TimelineFilter {
  const TimelineFilter({
    this.notebookId,
    this.type,
    this.pinnedOnly = false,
  });

  /// 笔记本 id；null = 不限
  final int? notebookId;

  /// 记录类型；null = 不限
  final EntryType? type;

  /// 只看置顶
  final bool pinnedOnly;

  bool get isEmpty => notebookId == null && type == null && !pinnedOnly;

  /// 已激活的条件个数（筛选条上的「清除」按钮据此显示数量）
  int get activeCount =>
      (notebookId == null ? 0 : 1) + (type == null ? 0 : 1) + (pinnedOnly ? 1 : 0);

  TimelineFilter copyWith({
    int? notebookId,
    EntryType? type,
    bool? pinnedOnly,
    bool clearNotebook = false,
    bool clearType = false,
  }) {
    return TimelineFilter(
      notebookId: clearNotebook ? null : (notebookId ?? this.notebookId),
      type: clearType ? null : (type ?? this.type),
      pinnedOnly: pinnedOnly ?? this.pinnedOnly,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineFilter &&
      other.notebookId == notebookId &&
      other.type == type &&
      other.pinnedOnly == pinnedOnly;

  @override
  int get hashCode => Object.hash(notebookId, type, pinnedOnly);

  @override
  String toString() =>
      'TimelineFilter(notebook: $notebookId, type: ${type?.name}, pinnedOnly: $pinnedOnly)';
}
