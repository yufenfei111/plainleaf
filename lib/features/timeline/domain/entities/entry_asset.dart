/// 条目图片资产领域实体（W8 详情页用）。
///
/// 纯 Dart，不依赖 Drift / Flutter——与 [TimelineEntry] 同层，由 Data 层映射产出。
class EntryAsset {
  const EntryAsset({
    required this.id,
    required this.sortIndex,
    required this.relPath,
    this.thumbPath,
    this.mediumPath,
    this.width,
    this.height,
  });

  final int id;

  /// 条目内排序（AssetsDao.byEntry 按此升序返回）
  final int sortIndex;

  /// 原图相对路径（`media/yyyy/mm/<uuid>.jpg`，以私有支持目录为基准）
  final String relPath;

  /// 缩略图相对路径（长边 400、q80）
  final String? thumbPath;

  /// 中号图相对路径（长边 1600、q82）
  final String? mediumPath;

  final int? width;
  final int? height;

  /// 详情页大图首选来源：**medium → thumb → 原图**。
  ///
  /// W6 性能红线：列表与网格禁止直接解码原图；详情页虽是单张全屏，
  /// 但手机相册原图动辄 4000px、数 MB，直接 Image.file 解码会明显卡顿、
  /// 内存峰值过高。medium（长边 1600）足以覆盖全屏显示，是唯一应当使用的来源。
  /// 只在 medium/thumb 双双缺失（历史数据未回填）时才回退原图，并应提示用户回填。
  String get preferredRelPath => mediumPath ?? thumbPath ?? relPath;

  /// 是否需要回填派生图（两者皆空 = 只能回退原图，属降级状态）
  bool get needsBackfill => mediumPath == null && thumbPath == null;
}
