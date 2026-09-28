import '../../../../core/media/asset_kind.dart';
import 'timeline_entry.dart';

/// 时间轴筛选条件（W7 组织能力；W20 增「附件类型」维度）
///
/// 放在 domain 层、保持不可变：UI 持有它、Repository 翻译成 SQL where，
/// 数据层不反向依赖 Flutter。
class TimelineFilter {
  const TimelineFilter({
    this.notebookId,
    this.type,
    this.pinnedOnly = false,
    this.attachmentKind,
  });

  /// 笔记本 id；null = 不限
  final int? notebookId;

  /// 记录类型；null = 不限
  final EntryType? type;

  /// 只看置顶
  final bool pinnedOnly;

  /// 只看**带某类附件**的记录；null = 不限（W20 P1-10）
  ///
  /// 为什么这个维度值得单独加：附件支持多种格式之后，"我记得给哪条记录挂过
  /// 一个 PDF"是最自然的检索意图，而按记录类型（笔记/日记）和按笔记本都答不了它。
  /// 注意语义是"**含**该类附件"而非"只有该类"——一条同时带图和 PDF 的记录，
  /// 在"PDF"条件下应当出现。
  final AssetKind? attachmentKind;

  bool get isEmpty =>
      notebookId == null && type == null && !pinnedOnly && attachmentKind == null;

  /// 已激活的条件个数（筛选条上的「清除」按钮据此显示数量）
  int get activeCount =>
      (notebookId == null ? 0 : 1) +
      (type == null ? 0 : 1) +
      (pinnedOnly ? 1 : 0) +
      (attachmentKind == null ? 0 : 1);

  TimelineFilter copyWith({
    int? notebookId,
    EntryType? type,
    bool? pinnedOnly,
    AssetKind? attachmentKind,
    bool clearNotebook = false,
    bool clearType = false,
    bool clearAttachmentKind = false,
  }) {
    return TimelineFilter(
      notebookId: clearNotebook ? null : (notebookId ?? this.notebookId),
      type: clearType ? null : (type ?? this.type),
      pinnedOnly: pinnedOnly ?? this.pinnedOnly,
      attachmentKind: clearAttachmentKind
          ? null
          : (attachmentKind ?? this.attachmentKind),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineFilter &&
      other.notebookId == notebookId &&
      other.type == type &&
      other.pinnedOnly == pinnedOnly &&
      other.attachmentKind == attachmentKind;

  @override
  int get hashCode =>
      Object.hash(notebookId, type, pinnedOnly, attachmentKind);

  @override
  String toString() =>
      'TimelineFilter(notebook: $notebookId, type: ${type?.name}, '
      'pinnedOnly: $pinnedOnly, attachmentKind: ${attachmentKind?.name})';
}
