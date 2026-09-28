import 'package:path/path.dart' as p;

/// 相册网格项（纯 Dart，不依赖 Drift / Flutter）
class GalleryAsset {
  const GalleryAsset({
    required this.id,
    required this.entryId,
    required this.relPath,
    required this.createdAt,
    this.thumbPath,
    this.mediumPath,
    this.originalName,
  });

  final int id;
  final int? entryId;

  /// 原图相对路径（media/…）
  final String relPath;

  /// 缩略图相对路径（thumb/…）；W4 期历史数据可能为 null → 回退原图
  final String? thumbPath;

  /// 中号图相对路径（medium/…）；单图查看用（W7 详情页）
  final String? mediumPath;

  /// 导入时的原始文件名（W20）；历史数据为 null
  final String? originalName;

  final DateTime createdAt;

  /// 展示名：原始文件名优先，缺失时回退盘上文件名。
  ///
  /// W20 起"保存到设备"用它作为目标文件名 —— 用户保存下来的文件应当与他在
  /// App 里看到的名字一致，而不是那一串 uuid。
  String get displayName {
    final name = originalName;
    if (name != null && name.trim().isNotEmpty) return name;
    return p.basename(relPath);
  }
}
