/// 相册网格项（纯 Dart，不依赖 Drift / Flutter）
class GalleryAsset {
  const GalleryAsset({
    required this.id,
    required this.entryId,
    required this.relPath,
    required this.createdAt,
    this.thumbPath,
    this.mediumPath,
  });

  final int id;
  final int? entryId;

  /// 原图相对路径（media/…）
  final String relPath;

  /// 缩略图相对路径（thumb/…）；W4 期历史数据可能为 null → 回退原图
  final String? thumbPath;

  /// 中号图相对路径（medium/…）；单图查看用（W7 详情页）
  final String? mediumPath;

  final DateTime createdAt;
}
