import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plainleaf/core/media/asset_kind.dart';

/// W17 多格式：类型模型与类型探测的用例。
///
/// 重点不是"认得出 jpg"，而是三条容易出错的行为：
///   ① 改名文件不能骗过判断（文件头优先于扩展名）
///   ② 容器格式必须靠扩展名细分（docx 与 zip 的文件头完全一样）
///   ③ 任何未知输入都不得抛异常 —— 未知格式要能落库，不能中断导入
Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

/// ISO BMFF 头：魔数 + `ftyp` + 品牌串
Uint8List _ftyp(String brand) => Uint8List.fromList([
      ...[0x00, 0x00, 0x00, 0x18],
      ...'ftyp'.codeUnits,
      ...brand.codeUnits,
    ]);

/// RIFF 头：`RIFF` + 4 字节长度 + 类型标记
Uint8List _riff(String tag) => Uint8List.fromList([
      ...'RIFF'.codeUnits,
      ...[0x00, 0x00, 0x00, 0x00],
      ...tag.codeUnits,
    ]);

void main() {
  group('AssetKind.fromStorage', () {
    test('已知取值原样还原', () {
      for (final kind in AssetKind.values) {
        expect(AssetKind.fromStorage(kind.name), kind);
      }
    });

    test('null / 空串 / 未知值一律降级为 other，且不抛异常', () {
      expect(AssetKind.fromStorage(null), AssetKind.other);
      expect(AssetKind.fromStorage(''), AssetKind.other);
      expect(AssetKind.fromStorage('audio_book'), AssetKind.other);
      expect(AssetKind.fromStorage('IMAGE'), AssetKind.other);
    });

    test('老数据的 image 取值可读（决定无需迁移回填）', () {
      expect(AssetKind.fromStorage('image'), AssetKind.image);
    });
  });

  group('AssetKind.hasThumbnailSource', () {
    test('只有 image/video/audio/pdf 需要进转码管线', () {
      expect(AssetKind.image.hasThumbnailSource, isTrue);
      expect(AssetKind.video.hasThumbnailSource, isTrue);
      expect(AssetKind.audio.hasThumbnailSource, isTrue);
      expect(AssetKind.pdf.hasThumbnailSource, isTrue);
    });

    test('document/archive/other 不生成缩略图，UI 用图标兜底', () {
      expect(AssetKind.document.hasThumbnailSource, isFalse);
      expect(AssetKind.archive.hasThumbnailSource, isFalse);
      expect(AssetKind.other.hasThumbnailSource, isFalse);
    });
  });

  group('AssetTypeDetector.detect · 文件头优先', () {
    test('图片内容被改名成 .pdf，仍判为 image（扩展名会骗人）', () {
      expect(
        AssetTypeDetector.detect(
          head: _bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]),
          extension: '.pdf',
        ),
        AssetKind.image,
      );
    });

    test('PNG / GIF / BMP 头', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D]), extension: ''),
        AssetKind.image,
      );
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x47, 0x49, 0x46, 0x38, 0x39]), extension: ''),
        AssetKind.image,
      );
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x42, 0x4D, 0x00, 0x00]), extension: ''),
        AssetKind.image,
      );
    });

    test('PDF 头 → pdf（即使扩展名是 .bin）', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x25, 0x50, 0x44, 0x46, 0x2D]), extension: '.bin'),
        AssetKind.pdf,
      );
    });

    test('音频头：fLaC / OggS / ID3', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x66, 0x4C, 0x61, 0x43, 0x00]), extension: ''),
        AssetKind.audio,
      );
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x4F, 0x67, 0x67, 0x53, 0x00]), extension: ''),
        AssetKind.audio,
      );
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x49, 0x44, 0x33, 0x03]), extension: ''),
        AssetKind.audio,
      );
    });

    test('压缩包头：Rar! / 7z', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x52, 0x61, 0x72, 0x21, 0x1A]), extension: ''),
        AssetKind.archive,
      );
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x37, 0x7A, 0xBC, 0xAF, 0x27]), extension: ''),
        AssetKind.archive,
      );
    });
  });

  group('AssetTypeDetector.detect · RIFF 容器', () {
    test('RIFF/WAVE → audio', () {
      expect(
        AssetTypeDetector.detect(head: _riff('WAVE'), extension: ''),
        AssetKind.audio,
      );
    });

    test('RIFF/WEBP → image', () {
      expect(
        AssetTypeDetector.detect(head: _riff('WEBP'), extension: ''),
        AssetKind.image,
      );
    });

    test('RIFF/AVI → video', () {
      expect(
        AssetTypeDetector.detect(head: _riff('AVI '), extension: ''),
        AssetKind.video,
      );
    });
  });

  group('AssetTypeDetector.detect · ISO BMFF（ftyp）', () {
    test('m4a 品牌 → audio', () {
      expect(
        AssetTypeDetector.detect(head: _ftyp('M4A '), extension: ''),
        AssetKind.audio,
      );
    });

    test('heic 品牌 → image', () {
      expect(
        AssetTypeDetector.detect(head: _ftyp('heic'), extension: ''),
        AssetKind.image,
      );
    });

    test('isom / qt 品牌 → video', () {
      expect(
        AssetTypeDetector.detect(head: _ftyp('isom'), extension: ''),
        AssetKind.video,
      );
      expect(
        AssetTypeDetector.detect(head: _ftyp('qt  '), extension: ''),
        AssetKind.video,
      );
    });
  });

  group('AssetTypeDetector.detect · 容器靠扩展名细分', () {
    test('ZIP 头 + docx → document（两者文件头完全一样）', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x50, 0x4B, 0x03, 0x04]), extension: '.docx'),
        AssetKind.document,
      );
    });

    test('ZIP 头 + xlsx → document', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x50, 0x4B, 0x03, 0x04]), extension: '.xlsx'),
        AssetKind.document,
      );
    });

    test('ZIP 头 + zip → archive', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x50, 0x4B, 0x03, 0x04]), extension: '.zip'),
        AssetKind.archive,
      );
    });

    test('OLE2 头（旧版 Office）+ doc → document', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0xD0, 0xCF, 0x11, 0xE0, 0xA1]), extension: '.doc'),
        AssetKind.document,
      );
    });

    test('OLE2 头 + 未知扩展名 → 兜底 document', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0xD0, 0xCF, 0x11, 0xE0, 0xA1]), extension: ''),
        AssetKind.document,
      );
    });
  });

  group('AssetTypeDetector.detect · 扩展名兜底与兜底契约', () {
    test('无文件头时靠扩展名', () {
      expect(
        AssetTypeDetector.detect(head: _bytes([]), extension: '.mp4'),
        AssetKind.video,
      );
      expect(
        AssetTypeDetector.detect(head: _bytes([]), extension: 'jpg'),
        AssetKind.image,
      );
      expect(
        AssetTypeDetector.detect(head: _bytes([]), extension: '.MD'),
        AssetKind.document,
      );
    });

    test('svg 归 document 而非 image（Flutter 原生与 image 包都渲染不了它）', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes('<?xml'.codeUnits), extension: '.svg'),
        AssetKind.document,
      );
    });

    test('完全未知的格式 → other，绝不抛异常（这是本功能的契约）', () {
      expect(
        AssetTypeDetector.detect(
            head: _bytes([0x01, 0x02, 0x03, 0x04]), extension: '.xyzabc'),
        AssetKind.other,
      );
      expect(
        AssetTypeDetector.detect(head: _bytes([]), extension: ''),
        AssetKind.other,
      );
      expect(
        AssetTypeDetector.detect(head: _bytes([]), extension: '.'),
        AssetKind.other,
      );
    });

    test('文件头比声明的签名短也不崩', () {
      expect(
        AssetTypeDetector.detect(head: _bytes([0x25, 0x50]), extension: ''),
        AssetKind.other,
      );
    });
  });
}
