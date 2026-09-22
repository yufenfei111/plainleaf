// 生成 Android 启动图标（W9 收尾）
//
// 为什么自己写而不用 flutter_launcher_icons：
//   它无非也是「裁切 + 多尺寸缩放」；而项目里已经有 image 包（纯 Dart），
//   自己写可以精确控制留白比例，且不引入新依赖、不依赖 ImageMagick 等本机工具。
//
// 用法：dart run tool/generate_launcher_icons.dart
//
// 关键处理：设计稿是 1024 方图且四周留白很大，直接缩放当图标会显得图形很小。
// 所以先按底色扫出内容包围盒，再以内容为中心裁一个正方形（含 PADDING 倍留白），
// 这样图标在桌面上才够饱满、又不会被裁到叶子。

import 'dart:io';

import 'package:image/image.dart' as img;

/// 设计稿（叶子 + 地平线）。
///
/// 用仓库内的相对路径而不是当初生成它的那个绝对路径——
/// 图标必须是**可复现**的：换台机器 clone 下来就能重新生成，
/// 否则这个脚本就成了一次性产物。
const _source = 'assets/branding/launcher-icon-source.jpg';

/// Android 各密度下的图标边长（px）
const _targets = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

/// 裁切后的正方形边长 = 内容最长边 × 该系数。
/// 1.25 意味着四周留白约 11%，mark 横向约填满图标的 80%（实测调出来的）。
const _padding = 1.25;

/// 判定「与底色不同」的三通道差值之和。
///
/// 这个值不能凭感觉给：本图 JPEG 噪点让阈值 20 时整幅纸底都被判为内容
/// （包围盒直接顶到 y=1023），等于没裁；实测阈值 ≥40 后包围盒稳定在
/// 605×366（叶子+地平线的真实范围），所以取 40。
const _tolerance = 40;

void main() {
  final file = File(_source);
  if (!file.existsSync()) {
    stderr.writeln('找不到设计稿：$_source');
    exitCode = 1;
    return;
  }

  final src = img.decodeImage(file.readAsBytesSync());
  if (src == null) {
    stderr.writeln('设计稿解码失败');
    exitCode = 1;
    return;
  }
  stdout.writeln('源图：${src.width} × ${src.height}');

  final box = _contentBox(src);
  stdout.writeln(
    '内容包围盒：x ${box.left}–${box.right}, y ${box.top}–${box.bottom}',
  );

  final side = (box.width > box.height ? box.width : box.height) * _padding;
  var left = (box.centerX - side / 2).round();
  var top = (box.centerY - side / 2).round();
  var size = side.round().clamp(1, src.width);
  // 贴边时把裁切框推回图内，避免出现空白填充
  if (left < 0) left = 0;
  if (top < 0) top = 0;
  if (left + size > src.width) left = src.width - size;
  if (top + size > src.height) top = src.height - size;

  final cropped = img.copyCrop(src, x: left, y: top, width: size, height: size);
  stdout.writeln('裁切：$size × $size @ ($left, $top)');

  for (final entry in _targets.entries) {
    final dir = Directory('android/app/src/main/res/${entry.key}');
    if (!dir.existsSync()) {
      stderr.writeln('跳过不存在的目录：${dir.path}');
      continue;
    }
    final resized = img.copyResize(
      cropped,
      width: entry.value,
      height: entry.value,
      interpolation: img.Interpolation.cubic,
    );
    final out = File('${dir.path}/ic_launcher.png');
    out.writeAsBytesSync(img.encodePng(resized));
    stdout.writeln('写入 ${out.path}  (${entry.value}×${entry.value})');
  }

  stdout.writeln('完成。');
}

/// 扫出与左上角底色明显不同的像素包围盒
_Box _contentBox(img.Image image) {
  final bg = image.getPixel(1, 1);
  var minX = image.width, minY = image.height, maxX = 0, maxY = 0;

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final diff = (p.r - bg.r).abs() + (p.g - bg.g).abs() + (p.b - bg.b).abs();
      if (diff <= _tolerance) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }

  // 整张图都是底色时，退回整图，避免出现 0 尺寸
  if (maxX <= minX || maxY <= minY) {
    return _Box(0, 0, image.width, image.height);
  }
  return _Box(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

/// 简易包围盒（image 4.x 没有公开的 Rectangle 类型，自己带一个更省事）
class _Box {
  const _Box(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width - 1;
  int get bottom => top + height - 1;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
}
