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
    this.mood,
    this.notebookId,
    this.notebookName,
    this.notebookSpace,
    this.firstAssetRelPath,
    this.firstAssetThumbPath,
  });

  final int id;
  final String uuid;
  final String title;
  final String plainText;
  final EntryType type;
  final EntryStatus status;
  final bool pinned;
  final DateTime entryDate;

  /// 心情 1–5 档（null = 未记录）
  final int? mood;
  final int? notebookId;
  final String? notebookName;
  final String? notebookSpace;

  /// 首图相对路径（W4 图片管线接入后用于卡片缩略图）
  final String? firstAssetRelPath;

  /// 首图缩略图相对路径（W6 两级缩略图；为空时回退原图）
  final String? firstAssetThumbPath;
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