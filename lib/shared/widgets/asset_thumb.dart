import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/media/asset_kind.dart';

/// 附件缩略图统一入口（W19）
///
/// ## 为什么必须收口
/// W17 让"任意格式的文件都能导入"，但展示层当时仍是各处自己写 `Image.file`。
/// 每个调用点都得自行判断「这个附件能不能渲染位图、渲染失败显示什么」，
/// 于是同一条 PDF 在不同页面表现不同：编辑器里是文件图标、详情页里是破图占位。
/// 更麻烦的是显示策略每调整一次要改 N 处，而 N 处**必然会漂移**。
///
/// 收口之后规则只有一条，且写在这里：
///   - 有可渲染的位图 → `Image.file`（**必须**限 `cacheWidth`，见下）
///   - 没有位图 → 类型图标 + 扩展名徽标
///   - 图片渲染失败 → 破图图标（这是**信息**：图坏了，不是"不支持该格式"）
///   - 非图片渲染失败 / 无位图 → 类型徽标（同理：这是"不认识该格式"的信息）
///
/// ## 性能红线（沿用 W6）
/// 缩略图位一律优先 `thumbPath`，并**必须**带 `cacheWidth`：
/// 64dp 的框里解码 4000×3000 的原图，单张就吃掉几十 MB 解码内存。
///
/// ## 为什么类型判定放在 [bitmapFor] 而不是调用点
/// "图片可以回退原图、其他类型只认 thumb"是一条策略。策略散在各调用点，
/// 就会出现"时间轴认得、那年今日不认得"这种半截修复。
class AssetThumb extends StatelessWidget {
  const AssetThumb({
    super.key,
    required this.kind,
    required this.size,
    required this.bitmapRelPath,
    this.root,
    this.originalName,
    this.fit = BoxFit.cover,
    this.showLabel = true,
    this.borderRadius,
  });

  /// 便捷构造：自动按附件语义挑位图来源（见 [bitmapFor]）。
  ///
  /// 调用点只需把库里那三列原样传进来，不必各自判断"该用 thumb 还是原图"。
  factory AssetThumb.forAsset({
    Key? key,
    required AssetKind kind,
    required double size,
    String? root,
    String? thumbPath,
    String? relPath,
    String? originalName,
    BoxFit fit = BoxFit.cover,
    bool showLabel = true,
    BorderRadius? borderRadius,
  }) {
    return AssetThumb(
      key: key,
      kind: kind,
      size: size,
      root: root,
      bitmapRelPath: bitmapFor(kind: kind, thumbPath: thumbPath, relPath: relPath),
      originalName: originalName,
      fit: fit,
      showLabel: showLabel,
      borderRadius: borderRadius,
    );
  }

  /// 附件类型（决定徽标图标）
  final AssetKind kind;

  /// 边长（正方形格）。由调用点给出，便于各处保持自己的信息密度。
  final double size;

  /// 可渲染位图的**相对**路径（相对支持目录）。为 null 时直接显示类型徽标。
  final String? bitmapRelPath;

  /// 支持目录；未解析出来时（启动最初几十毫秒）显示占位色块，
  /// **不要**拿 null 去拼路径——那会得到相对路径指向进程工作目录的破图。
  final String? root;

  /// 原始文件名，仅用于徽标上的扩展名
  final String? originalName;

  final BoxFit fit;

  /// 是否在图标下方显示扩展名。没有扩展名可显示时自动省略。
  final bool showLabel;

  final BorderRadius? borderRadius;

  /// 从附件的三个路径列里挑出"能不能用位图渲染"。
  ///
  /// - **图片**：`thumb → 原图`。历史数据（W4 期）没有 thumb，回退原图是
  ///   唯一的显示途径，配合 `cacheWidth` 解码代价可接受。
  /// - **其他类型**：只认 `thumb`。P1 之前音视频/PDF 都没有缩略图，返回 null →
  ///   显示类型徽标；等 P1 补上缩略图，**这里无需改动**，有 thumb 就自动渲染。
  ///   反过来说，若这里也回退原文件，`Image.file` 会把 PDF 二进制喂给解码器，
  ///   稳定失败并每次触发一次异常 —— 比直接显示图标更糟。
  static String? bitmapFor({
    required AssetKind kind,
    String? thumbPath,
    String? relPath,
  }) {
    final candidate =
        kind == AssetKind.image ? (thumbPath ?? relPath) : thumbPath;
    return (candidate == null || candidate.isEmpty) ? null : candidate;
  }

  @override
  Widget build(BuildContext context) {
    final base = root;
    final rel = bitmapRelPath;
    final scheme = Theme.of(context).colorScheme;

    Widget child;
    if (base == null) {
      // 支持目录尚未解析：占位而不是渲染失败态。这两件事对用户不同 ——
      // 一个是"还在准备"，一个是"这个文件我没法显示"。
      child = ColoredBox(color: scheme.surfaceContainerHighest);
    } else if (rel == null) {
      child = _TypeBadge(
        kind: kind,
        size: size,
        originalName: originalName,
        showLabel: showLabel,
      );
    } else {
      child = Image.file(
        File(p.join(base, rel)),
        width: size,
        height: size,
        fit: fit,
        // DPR 必须乘上：3x 屏上按逻辑像素解码会让图放大后糊成一团
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, _, _) => _ErrorContent(
          kind: kind,
          size: size,
          originalName: originalName,
          showLabel: showLabel,
        ),
      );
    }

    final box = SizedBox(width: size, height: size, child: child);
    final radius = borderRadius;
    return radius == null ? box : ClipRRect(borderRadius: radius, child: box);
  }
}

/// 渲染失败时显示什么 —— 这里承载了一条判断：**失败的原因要说出来**。
///
/// - 图片失败：破图图标。用户该知道"图坏了"，而不是误以为这是个文档。
/// - 其他类型失败：类型徽标。它们本就没有内置渲染能力，徽标才是准确描述。
class _ErrorContent extends StatelessWidget {
  const _ErrorContent({
    required this.kind,
    required this.size,
    required this.originalName,
    required this.showLabel,
  });

  final AssetKind kind;
  final double size;
  final String? originalName;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (kind == AssetKind.image) {
      return ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          size: (size * 0.4).clamp(16, 48),
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    return _TypeBadge(
      kind: kind,
      size: size,
      originalName: originalName,
      showLabel: showLabel,
    );
  }
}

/// 非图片附件（以及尚未转码的图片）的格子：类型图标 + 扩展名
///
/// 只显示扩展名而不是完整文件名：格子里放不下「作业第三章.pdf」，
/// 截断成半截名字反而更难看。完整名字留给详情页附件区与点开后的动作。
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.kind,
    required this.size,
    required this.originalName,
    required this.showLabel,
  });

  final AssetKind kind;
  final double size;
  final String? originalName;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 拿不到原始文件名时退到类型中文名（PDF / 文档 / 压缩包）——
    // 时间轴卡片只有 kind，没有文件名，这条兜底正是给它用的。
    final label = showLabel
        ? assetBadgeLabel(originalName: originalName, kind: kind)
        : '';
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            assetKindIcon(kind),
            size: (size * 0.34).clamp(14, 40),
            color: scheme.onSurfaceVariant,
          ),
          if (label.isNotEmpty) ...[
            SizedBox(height: (size * 0.06).clamp(2, 6)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: (size * 0.14).clamp(9, 13),
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 附件类型 → 图标。**唯一定义处**：此前编辑器、时间轴各写一份 switch，
/// 加一种类型时漏掉任何一处都会让该类型在某个页面显示成默认图标。
IconData assetKindIcon(AssetKind kind) => switch (kind) {
      AssetKind.image => Icons.image_outlined,
      AssetKind.video => Icons.movie_outlined,
      AssetKind.audio => Icons.audiotrack_outlined,
      AssetKind.pdf => Icons.picture_as_pdf_outlined,
      AssetKind.document => Icons.description_outlined,
      AssetKind.archive => Icons.folder_zip_outlined,
      AssetKind.other => Icons.insert_drive_file_outlined,
    };

/// 徽标上的一行字：扩展名优先（`PDF` / `DOCX`），没有则退到类型中文名。
///
/// 扩展名从**原始文件名**取而不是盘上路径：盘上落的是 uuid，
/// 两者扩展名相同但用意不同 —— 传 originalName 让这里能对"文件名被改过"
/// 这类情况给出用户实际看到的那个扩展名。
String assetBadgeLabel({
  String? originalName,
  String? relPath,
  AssetKind? kind,
}) {
  final source = originalName ?? relPath;
  if (source != null) {
    final ext = p.extension(source).replaceFirst('.', '').trim();
    if (ext.isNotEmpty) return ext.toUpperCase();
  }
  return kind?.label ?? '';
}

/// 字节数 → 人类可读（`1.2 MB`）。未知返回 null，由调用点决定省略还是占位。
///
/// 用 1024 进制：与系统文件管理器一致，用户不会拿它跟"标称 1GB"做精确对比。
String? formatFileSize(int? bytes) {
  if (bytes == null || bytes < 0) return null;
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // 小于 10 时留一位小数（1.2 MB 比 1 MB 有信息量），否则取整（345 MB 就够）
  final text = value >= 10 ? value.round().toString() : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// 时长（毫秒）→ `3:45` / `1:02:07`。未知或非正数返回 null。
///
/// 分:秒 与 时:分:秒 两档：短视频/歌曲用前者才不啰嗦，而超过一小时用
/// `63:45` 这种写法会让人读不出来是多少。
String? formatDuration(int? milliseconds) {
  if (milliseconds == null || milliseconds <= 0) return null;
  final totalSeconds = milliseconds ~/ 1000;
  final seconds = totalSeconds % 60;
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}
