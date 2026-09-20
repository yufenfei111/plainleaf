import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

/// 两级缩略图管线（W6，§4.3 媒体文件 + §5.2 性能红线）
///
/// - thumb：长边 400、q80 —— 时间轴卡片与相册网格使用（列表滚动的主角）
/// - medium：长边 1600、q82 —— 单图查看使用（W7 详情页）
/// - 全部转码跑在 **Isolate** 里：解码/缩放/编码是纯 CPU 活，
///   放在主线程会直接和 16ms 的帧预算抢时间，是列表卡顿的典型来源。
/// - `bakeOrientation`：手机照片普遍带 EXIF 方向标记，不烘焙会出现
///   "竖拍照片在列表里横躺"的经典问题。
/// - 顺带算出 §4.3 要求的 hash_sha256 与原始宽高/字节数，一次 IO 全拿到。
class ThumbnailPipeline {
  static const int thumbLongEdge = 400;
  static const int mediumLongEdge = 1600;
  static const int thumbQuality = 80;
  static const int mediumQuality = 82;

  /// 生成两级缩略图。入参/出参全是字符串与数字，确保在 isolate 间可传递。
  /// [thumbAbs]/[mediumAbs] 的父目录会自动创建。
  Future<DerivedImages> generate({
    required String sourceAbs,
    required String thumbAbs,
    required String mediumAbs,
    required String thumbRel,
    required String mediumRel,
  }) async {
    final map = await Isolate.run(
      () => _encode(
        sourceAbs: sourceAbs,
        thumbAbs: thumbAbs,
        mediumAbs: mediumAbs,
      ),
    );
    return DerivedImages(
      thumbRel: thumbRel,
      mediumRel: mediumRel,
      width: map['width'] as int,
      height: map['height'] as int,
      sizeBytes: map['sizeBytes'] as int,
      hashSha256: map['hashSha256'] as String,
    );
  }

  /// isolate 内执行：读原图 → 烘焙方向 → 两级缩放编码 → 算 sha256。
  /// 只返回 Map（跨 isolate 最稳的可发送类型）。
  static Map<String, Object> _encode({
    required String sourceAbs,
    required String thumbAbs,
    required String mediumAbs,
  }) {
    final bytes = File(sourceAbs).readAsBytesSync();
    // 损坏/非图片文件会让解码器抛 RangeError（属于 Error 而非 Exception），
    // 统一转成 FormatException，调用方只需按异常降级，不必区分错误类型。
    final decoded = _safeDecode(bytes);
    if (decoded == null) {
      throw FormatException('无法解码图片：$sourceAbs');
    }
    final baked = img.bakeOrientation(decoded);

    File(thumbAbs).parent.createSync(recursive: true);
    File(thumbAbs).writeAsBytesSync(
      img.encodeJpg(_resize(baked, thumbLongEdge), quality: thumbQuality),
    );

    File(mediumAbs).parent.createSync(recursive: true);
    File(mediumAbs).writeAsBytesSync(
      img.encodeJpg(_resize(baked, mediumLongEdge), quality: mediumQuality),
    );

    return {
      'width': baked.width,
      'height': baked.height,
      'sizeBytes': bytes.length,
      'hashSha256': sha256.convert(bytes).toString(),
    };
  }

  static img.Image? _safeDecode(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } on Object {
      return null;
    }
  }

  /// 按长边等比缩放；**小于目标边时不放大**（避免小图被插值变糊、白耗 IO）
  static img.Image _resize(img.Image src, int longEdge) {
    final w = src.width;
    final h = src.height;
    if (w <= longEdge && h <= longEdge) return src;
    if (w >= h) {
      return img.copyResize(src, width: longEdge);
    }
    return img.copyResize(src, height: longEdge);
  }
}

/// 转码产物：落库字段与相对路径
class DerivedImages {
  const DerivedImages({
    required this.thumbRel,
    required this.mediumRel,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.hashSha256,
  });

  final String thumbRel;
  final String mediumRel;
  final int width;
  final int height;
  final int sizeBytes;
  final String hashSha256;
}
