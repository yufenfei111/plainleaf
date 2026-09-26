import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// 附件类型（W17 多格式文件支持）
///
/// **为什么要显式建模类型**：在此之前整条链路是「图片专用」的 ——
/// 存储层其实不假设格式（`MediaStorage.importFile` 用 `p.extension()` 保留任意扩展名），
/// 但缩略图管线硬依赖图片解码、展示层有 4 处直接 `Image.file`。
/// 把「类型」显式建模出来，才能把散落的「图片假设」逐个换成「按类型分派」。
///
/// 存库用本枚举的 [name]（`assets.kind` 是 text 字段，默认 `'image'`），
/// 因此**老数据不需要迁移**即可继续读；遇到不认识的值一律降级为 [AssetKind.other]，
/// **绝不抛异常** —— 未知格式必须能被记录、备份、导出。
enum AssetKind {
  /// 图片：走现有两级缩略图管线
  image,

  /// 视频：缩略图为抽帧（P1）
  video,

  /// 音频：缩略图为内嵌封面（P1）
  audio,

  /// PDF：缩略图为首页渲染（P1）
  pdf,

  /// 文档：doc/docx/xls/ppt/txt/md… 显示类型图标，点开交给系统
  document,

  /// 压缩包：zip/rar/7z…
  archive,

  /// 其他一切未知格式 —— 落在这里而不是报错，是本功能的契约
  other;

  /// 从库里的字符串还原。无法识别时降级为 [other]，不抛异常。
  static AssetKind fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return AssetKind.other;
    for (final kind in AssetKind.values) {
      if (kind.name == raw) return kind;
    }
    return AssetKind.other;
  }

  /// 是否有可能生成缩略图（决定要不要进转码管线）。
  /// [other] / [document] / [archive] 不生成缩略图，UI 直接用类型图标。
  bool get hasThumbnailSource => switch (this) {
        AssetKind.image ||
        AssetKind.video ||
        AssetKind.audio ||
        AssetKind.pdf =>
          true,
        AssetKind.document || AssetKind.archive || AssetKind.other => false,
      };
}

/// 附件类型探测：**文件头（magic bytes）优先，扩展名兜底**
///
/// 为什么不只看扩展名：改名文件会骗过判断（把图片存成 `.pdf`、下载来的文件没有扩展名）。
/// 类型判错的代价是把图片当成未知文件、列表里只剩一个图标。
/// 读文件头只要前 16 字节，成本可忽略。
///
/// 为什么也不能只看文件头：`docx/xlsx/pptx`（新版 Office）与 `zip` **都是 PK 开头的 ZIP**，
/// `doc/xls/ppt`（旧版）都是 OLE2 容器 —— 这类「容器格式」必须靠扩展名才能细分。
/// 所以策略是：**强特征以文件头为准；容器与无头文件以扩展名为准**。
class AssetTypeDetector {
  /// 读多少字节。RIFF 系列（wav/webp/avi）与 ISO BMFF（mp4/heic/m4a）
  /// 的类型标记都在 offset 8，所以要够 12 字节；取 16 留点余量。
  static const int headBytes = 16;

  /// 按真实文件探测。文件读不到时退化为按扩展名判断，**不抛异常**。
  static AssetKind detectFile(String absPath) {
    final extension = p.extension(absPath);
    Uint8List head;
    try {
      final raf = File(absPath).openSync();
      try {
        head = raf.readSync(headBytes);
      } finally {
        raf.closeSync();
      }
    } on FileSystemException {
      head = Uint8List(0);
    }
    return detect(head: head, extension: extension);
  }

  /// 纯函数版本（便于单测，不需要真实文件）。
  static AssetKind detect({
    required Uint8List head,
    required String extension,
  }) {
    final ext = extension.startsWith('.')
        ? extension.substring(1).toLowerCase()
        : extension.toLowerCase();

    // ── 1) 有唯一强特征的：以文件头为准（扩展名可能被改过）──
    if (_has(head, const [0x25, 0x50, 0x44, 0x46])) return AssetKind.pdf; // %PDF
    if (_has(head, const [0xFF, 0xD8, 0xFF])) return AssetKind.image; // JPEG
    if (_has(head, const [0x89, 0x50, 0x4E, 0x47])) return AssetKind.image; // PNG
    if (_has(head, const [0x47, 0x49, 0x46, 0x38])) return AssetKind.image; // GIF8
    if (_has(head, const [0x42, 0x4D])) return AssetKind.image; // BMP
    if (_has(head, const [0x66, 0x4C, 0x61, 0x43])) return AssetKind.audio; // fLaC
    if (_has(head, const [0x4F, 0x67, 0x67, 0x53])) return AssetKind.audio; // OggS
    if (_has(head, const [0x49, 0x44, 0x33])) return AssetKind.audio; // ID3（mp3）
    if (_has(head, const [0xFF, 0xFB])) return AssetKind.audio; // mp3 帧同步
    if (_has(head, const [0x52, 0x61, 0x72, 0x21])) return AssetKind.archive; // Rar!
    if (_has(head, const [0x37, 0x7A, 0xBC, 0xAF])) return AssetKind.archive; // 7z

    // ── 2) RIFF 容器：种类在 offset 8 的四字节里 ──
    if (_has(head, const [0x52, 0x49, 0x46, 0x46]) && head.length >= 12) {
      final tag = String.fromCharCodes(head.sublist(8, 12));
      if (tag == 'WAVE') return AssetKind.audio;
      if (tag == 'WEBP') return AssetKind.image;
      return AssetKind.video; // AVI 及其他 RIFF 变体
    }

    // ── 3) ISO BMFF（ftyp）：mp4 / mov / m4a / heic 共用一个头 ──
    if (head.length >= 12 && String.fromCharCodes(head.sublist(4, 8)) == 'ftyp') {
      final brand = String.fromCharCodes(head.sublist(8, 12));
      if (brand.startsWith('heic') ||
          brand.startsWith('heix') ||
          brand.startsWith('mif1')) {
        return AssetKind.image; // HEIC/HEIF 系
      }
      if (brand.startsWith('M4A') || brand.startsWith('mp4a')) {
        return AssetKind.audio;
      }
      return AssetKind.video; // mp4 / mov / 3gp 等
    }

    // ── 4) 容器格式：必须靠扩展名细分（docx 与 zip 的文件头完全一样）──
    if (_has(head, const [0x50, 0x4B])) {
      return _byExtension(ext, fallback: AssetKind.archive);
    }
    if (_has(head, const [0xD0, 0xCF, 0x11, 0xE0])) {
      return _byExtension(ext, fallback: AssetKind.document); // OLE2
    }

    // ── 5) 没有可用文件头：纯靠扩展名 ──
    return _byExtension(ext, fallback: AssetKind.other);
  }

  static AssetKind _byExtension(String ext, {required AssetKind fallback}) {
    if (ext.isEmpty) return fallback;
    if (ext == 'pdf') return AssetKind.pdf;
    if (_imageExt.contains(ext)) return AssetKind.image;
    if (_videoExt.contains(ext)) return AssetKind.video;
    if (_audioExt.contains(ext)) return AssetKind.audio;
    if (_documentExt.contains(ext)) return AssetKind.document;
    if (_archiveExt.contains(ext)) return AssetKind.archive;
    return fallback;
  }

  static const Set<String> _imageExt = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif',
  };

  static const Set<String> _videoExt = {
    'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp', 'flv', 'wmv',
    'mpg', 'mpeg',
  };

  static const Set<String> _audioExt = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma', 'amr', 'aiff',
  };

  /// 注意 `svg` 与 `tif/tiff` 的去向：
  /// - `svg` 归 document 而非 image —— 它是 XML 文本，Flutter 原生 `Image` 与
  ///   `image` 包都渲染不了（要 flutter_svg）。归 image 会让它在展示层必然失败，
  ///   归 document 则走「图标 + 交给系统打开」，行为可预期。
  /// - `tif/tiff` 仍归 image，但 `image` 包对其支持有限：解码失败时管线已按
  ///   FormatException 降级，最终表现是"没有缩略图、显示图标"，不会崩。
  static const Set<String> _documentExt = {
    'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
    'txt', 'md', 'rtf', 'csv', 'tsv', 'json', 'xml', 'yaml', 'yml',
    'html', 'htm', 'epub', 'svg', 'tif', 'tiff',
  };

  static const Set<String> _archiveExt = {
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz',
  };

  static bool _has(Uint8List data, List<int> signature) {
    if (data.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (data[i] != signature[i]) return false;
    }
    return true;
  }
}
