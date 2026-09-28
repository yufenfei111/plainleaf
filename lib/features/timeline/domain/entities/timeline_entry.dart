import '../../../../core/media/asset_kind.dart';

/// 记录类型（与 entries.type 字符串互转）
enum EntryType {
  note('笔记'),
  diary('日记'),
  quick('速记'),
  todo('待办');

  const EntryType(this.label);

  final String label;

  static EntryType fromName(String name) =>
      values.firstWhere((t) => t.name == name, orElse: () => EntryType.note);
}

/// 记录状态（与 entries.status 字符串互转）
enum EntryStatus {
  draft('草稿'),
  normal('已发布'),
  archived('已归档');

  const EntryStatus(this.label);

  final String label;

  static EntryStatus fromName(String name) =>
      values.firstWhere((s) => s.name == name, orElse: () => EntryStatus.normal);
}

/// 时间轴领域实体（纯 Dart，不依赖 Drift / Flutter）
class TimelineEntry {
  const TimelineEntry({
    required this.id,
    required this.uuid,
    required this.title,
    required this.plainText,
    required this.type,
    required this.status,
    required this.pinned,
    required this.entryDate,
    required this.updatedAt,
    this.mood,
    this.notebookId,
    this.notebookName,
    this.notebookSpace,
    this.firstAssetRelPath,
    this.firstAssetThumbPath,
    this.firstAttachmentKind,
    this.attachmentCount = 0,
    this.contentDelta,
  });

  final int id;
  final String uuid;
  final String title;
  final String plainText;
  final EntryType type;
  final EntryStatus status;
  final bool pinned;
  final DateTime entryDate;

  /// 最近一次修改时间（回收站剩余保留天数据此计算）
  final DateTime updatedAt;

  /// 心情 1–5 档（null = 未记录）
  final int? mood;
  final int? notebookId;
  final String? notebookName;
  final String? notebookSpace;

  /// 首图相对路径（W4 图片管线接入后用于卡片缩略图）
  final String? firstAssetRelPath;

  /// 首图缩略图相对路径（W6 两级缩略图；为空时回退原图）
  final String? firstAssetThumbPath;

  /// 首个附件（**任意类型**，按 sortIndex）的类型；无附件为 null（W19）
  ///
  /// 用途只有一个：卡片**没有图片可显示**但有附件时，用来给出准确的类型图标。
  /// 在此之前这类记录显示的是「记录类型图标」（日记本 / 闪电），
  /// 用户看不出"这条记录挂着个 PDF"。
  ///
  /// 注意与 [firstAssetRelPath] 的区别：后者只认图片（`AssetsDao._rowsFor` 按
  /// `kind='image'` 选首图），本字段认全部类型，两者在混合附件时**可能指向不同文件**。
  final AssetKind? firstAttachmentKind;

  /// 该记录的全部附件数（含图片），0 表示无附件（W19）
  final int attachmentCount;

  /// 是否有附件（卡片据此决定要不要显示数量角标）
  bool get hasAttachments => attachmentCount > 0;

  /// quill 正文 Delta JSON（W8 详情页渲染富文本；旧数据或纯文本为空串）
  final String? contentDelta;
}

/// 新建/更新记录草稿（TimelineRepository.saveEntry / updateEntry 的入参）
class EntryDraft {
  const EntryDraft({
    required this.title,
    required this.plainText,
    this.type = EntryType.note,
    this.status = EntryStatus.normal,
    this.mood,
    this.notebookId,
    this.entryDate,
    this.contentDelta = '',
  });

  final String title;
  final String plainText;
  final EntryType type;
  final EntryStatus status;
  final int? mood;
  final int? notebookId;
  final DateTime? entryDate;

  /// flutter_quill Delta JSON
  final String contentDelta;
}