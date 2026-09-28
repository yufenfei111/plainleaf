import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// 音频元信息（W20 P1-9）
///
/// 只要两样东西：**时长**（填 `assets.durationMs`，字段 W4 建表时就预留了）
/// 与**内嵌封面**（用来生成缩略图，没有就照旧显示类型徽标）。
class AudioInfo {
  const AudioInfo({this.durationMs, this.coverBytes, this.coverMimeType});

  /// 时长；解析不出为 null（残缺文件、不支持的容器）
  final int? durationMs;

  /// 内嵌封面的原始字节（通常是 JPEG/PNG）；没有封面为 null
  final Uint8List? coverBytes;

  /// 封面 MIME，仅用于日志与判断格式；不参与落盘命名
  final String? coverMimeType;

  bool get hasCover => coverBytes != null && coverBytes!.isNotEmpty;

  static const AudioInfo none = AudioInfo();
}

/// 读音频时长与内嵌封面（W20 P1-9）
///
/// ## 为什么用 `audio_metadata_reader`
/// 它**纯 Dart**，自己解析 ID3v2 / MP4 ilst / Vorbis Comments，不走平台通道。
/// 本项目此前每引入一个平台插件都要付出真机验证的代价（AGP 9 与 win32 的
/// 冲突已经堵死过 file_picker），而这一项是本阶段唯一能"本机验完就交付"的。
///
/// ## 为什么放 Isolate
/// 读元信息要按容器结构定位到标签区，一首歌几 MB 到几十 MB、封面可能是一张
/// 1500×1500 的图 —— 全部在主线程做会和 16ms 的帧预算抢时间，
/// 与 `ThumbnailPipeline` 同一口径。
///
/// ## 失败一律降级
/// 不支持的容器（`aac` / `wma` / `amr` 不在该库的支持列表里）、被截断的文件、
/// 没有任何标签的文件 —— 全部返回 [AudioInfo.none]。
/// **"读不出元信息"绝不能让"挂接附件"失败**：文件本身还是好好地存进去了，
/// 用户要的是把文件记下来，时长与封面只是加分项。
class AudioMetadataProbe {
  const AudioMetadataProbe();

  Future<AudioInfo> probe(String absPath) async {
    final map = await Isolate.run(() => _readSync(absPath));
    final ms = map['durationMs'] as int?;
    return AudioInfo(
      durationMs: ms,
      coverBytes: map['coverBytes'] as Uint8List?,
      coverMimeType: map['coverMimeType'] as String?,
    );
  }

  /// isolate 内执行；只返回可发送类型（Map / 基本类型 / Uint8List）
  static Map<String, Object?> _readSync(String absPath) {
    try {
      final file = File(absPath);
      if (!file.existsSync()) return _none();
      // getImage: true 才会真的解析封面；默认 false 是为了批量扫描时的速度
      final meta = readMetadata(file, getImage: true);
      final cover = _pickCover(meta.pictures);
      return {
        'durationMs': meta.duration?.inMilliseconds,
        'coverBytes': cover?.bytes,
        'coverMimeType': cover?.mimetype,
      };
    } on Object {
      // MetadataParserException / NoMetadataParserException /
      // 以及任何解析实现里的越界等 —— 一律视为"读不出"，不上抛。
      return _none();
    }
  }

  static Map<String, Object?> _none() => const {
        'durationMs': null,
        'coverBytes': null,
        'coverMimeType': null,
      };

  /// 挑封面：**正封面优先**。
  ///
  /// 一首歌可能同时带正封面、封底、艺术家照片。直接取第一张会在某些 tag 上
  /// 拿到封底或一张 Logo —— 那种"缩略图是张不明图片"比没有封面更难理解。
  static Picture? _pickCover(List<Picture> pictures) {
    if (pictures.isEmpty) return null;
    final usable = pictures.where((p) => p.bytes.isNotEmpty);
    if (usable.isEmpty) return null;
    for (final p in usable) {
      if (p.pictureType == PictureType.coverFront) return p;
    }
    // 没有标注类型（很多 tag 写 other）：退到第一张有内容的
    return usable.first;
  }
}
