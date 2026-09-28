import 'package:path/path.dart' as p;

import '../../../../core/media/asset_kind.dart';

/// 条目附件领域实体（W8 详情页用；W19 起携带类型与原始文件名）。
///
/// 纯 Dart，不依赖 Drift / Flutter——与 [TimelineEntry] 同层，由 Data 层映射产出。
///
/// **为什么 [kind] 是必填**：W17 之前这条链路只有图片，实体里没有类型也不会错；
/// 多格式之后"类型"是所有展示决策的唯一依据（能不能渲染位图、该显示哪个图标）。
/// 给默认值等于给未来的调用点留一个"忘了传就静默退化成图片"的口子 ——
/// 这类默认值产生的 bug 不会报错，只会让 PDF 显示成破图。
class EntryAsset {
  const EntryAsset({
    required this.id,
    required this.sortIndex,
    required this.relPath,
    required this.kind,
    this.thumbPath,
    this.mediumPath,
    this.originalName,
    this.mimeType,
    this.sizeBytes,
    this.durationMs,
    this.width,
    this.height,
  });

  final int id;

  /// 条目内排序（AssetsDao.byEntry / allByEntry 按此升序返回）
  final int sortIndex;

  /// 原文件相对路径（`media/yyyy/mm/<uuid>.<ext>`，以私有支持目录为基准）
  final String relPath;

  /// 附件类型（W19）：决定渲染位图还是类型徽标
  final AssetKind kind;

  /// 缩略图相对路径（长边 400、q80）
  final String? thumbPath;

  /// 中号图相对路径（长边 1600、q82）
  final String? mediumPath;

  /// 导入时的原始文件名（如「作业第三章.pdf」）
  ///
  /// 非图片附件**必须**显示它：盘上落的是 uuid，用户看到一串 uuid 毫无意义。
  /// 历史数据（W17 之前）为空，读取端用 [displayName] 回退到文件名。
  final String? originalName;

  /// MIME 类型（W17 随导入写入；历史数据为空）
  final String? mimeType;

  /// 字节数（导入时取源文件大小；历史数据为空）
  final int? sizeBytes;

  /// 音视频时长（毫秒）（W20 P1-9 起对音频填充）。
  ///
  /// 字段 W4 建表时就预留了；图片 / 文档等类型恒为 null。
  final int? durationMs;

  final int? width;
  final int? height;

  /// 详情页大图首选来源：**medium → thumb → 原图**。
  ///
  /// W6 性能红线：列表与网格禁止直接解码原图；详情页虽是单张全屏，
  /// 但手机相册原图动辄 4000px、数 MB，直接 Image.file 解码会明显卡顿、
  /// 内存峰值过高。medium（长边 1600）足以覆盖全屏显示，是唯一应当使用的来源。
  /// 只在 medium/thumb 双双缺失（历史数据未回填）时才回退原图，并应提示用户回填。
  String get preferredRelPath => mediumPath ?? thumbPath ?? relPath;

  /// 供展示的名字：原始文件名优先，缺失时回退盘上文件名（uuid.ext）。
  /// 回退值不理想但至少带扩展名，比空白强。
  String get displayName {
    final name = originalName;
    if (name != null && name.trim().isNotEmpty) return name;
    return p.basename(relPath);
  }

  /// 是否是有位图来源的附件（决定能否渲染缩略图/大图）。
  ///
  /// 注意这只是"类型允许"，不代表盘上确实有图：历史数据可能还没转码。
  /// 真正的渲染判定交给 `AssetThumb.bitmapFor`（它同时看 kind 与路径）。
  bool get isImage => kind == AssetKind.image;

  /// 是否需要回填派生图（两者皆空 = 只能回退原图，属降级状态）
  bool get needsBackfill => mediumPath == null && thumbPath == null;
}
