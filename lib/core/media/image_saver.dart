import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../errors/app_exception.dart';
import 'attachment_handoff.dart';

/// 保存去向（决定提示文案）
enum SaveOutcome {
  /// 进了系统相册（Android / iOS）
  gallery,

  /// 落到了磁盘上的目录（桌面端）
  directory,
}

class SaveResult {
  const SaveResult({required this.outcome, required this.detail});

  final SaveOutcome outcome;

  /// gallery：空串；directory：完整落盘路径
  final String detail;

  String get userMessage => switch (outcome) {
        SaveOutcome.gallery => '已保存到系统相册',
        SaveOutcome.directory => '已保存到 $detail',
      };
}

/// 把相册里的图片保存到设备（W15 需求 3）
///
/// ## 分平台策略（为什么不写一套代码走到底）
/// - **Android / iOS**：交给系统相册（`gal`）。在这两个平台上，「保存到本地」
///   唯一符合直觉的含义就是"这张图出现在系统相册里"——若只是复制进 App 私有目录，
///   用户打开系统相册根本找不到，等于没保存。
/// - **桌面（Windows/macOS/Linux）**：系统里没有"相册"这个概念，
///   于是落到「下载」目录并把完整路径回给用户，与既有 Markdown/PDF 导出的做法一致。
///
/// ## 为什么要抽成接口
/// `gal` 走平台通道，`flutter test` 里调用必抛 MissingPluginException。
/// 保存流程（源文件解析、重名处理、异常映射）要能进 CI，就必须能把实现换掉。
abstract class ImageSaver {
  /// [asName]：希望保存成什么名字（通常是附件的**原始文件名**）。
  ///
  /// W20 起才有：此前桌面端用 `basename(sourcePath)`，而盘上是 uuid ——
  /// 用户保存下来的文件叫 `0f3a9c….jpg`，与他在 App 里看到的名字对不上。
  /// 命名规则与"交给系统打开"共用 `safeDisplayFileName`，
  /// 两条链路各写一份清理逻辑的结局必然是同一个附件两个名字。
  ///
  /// 注意：**平台相册实现会忽略它**（见 [GalleryImageSaver]），这是平台限制。
  Future<SaveResult> save(String sourcePath, {String? asName});
}

/// 系统相册实现（Android / iOS）
class GalleryImageSaver implements ImageSaver {
  const GalleryImageSaver();

  @override
  Future<SaveResult> save(String sourcePath, {String? asName}) async {
    try {
      // 注意 gal 只接受 album、**不支持自定义文件名**：相册里的命名由系统决定。
      // 所以这里刻意忽略 asName，也不为了"统一命名"再复制一遍文件 ——
      // 在系统相册里"名字"本来就不是用户检索照片的方式（那是相册自己的事）。
      await Gal.putImage(sourcePath);
    } on GalException catch (error) {
      throw ExportException(_describe(error));
    } on MissingPluginException {
      // 平台通道缺失（宿主没注册插件，或跑在测试宿主里）：
      // 归成"当前环境不支持"，而不是把一个 MissingPluginException 甩给用户。
      throw const ExportException('当前环境不支持保存到系统相册');
    }
    return const SaveResult(outcome: SaveOutcome.gallery, detail: '');
  }

  /// 把平台错误翻译成"用户下一步能做什么"，而不是把 GalException 甩出去
  String _describe(GalException error) => switch (error.type) {
        GalExceptionType.accessDenied =>
          '没有相册写入权限，请到系统设置里允许素页访问照片',
        GalExceptionType.notEnoughSpace => '设备存储空间不足，保存失败',
        GalExceptionType.notSupportedFormat => '这个图片格式系统相册不支持',
        _ => '保存到相册失败，请重试',
      };
}

/// 桌面实现：落到「下载」目录；**重名自动加序号，绝不覆盖既有文件**
class DesktopImageSaver implements ImageSaver {
  const DesktopImageSaver();

  @override
  Future<SaveResult> save(String sourcePath, {String? asName}) async {
    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final target = _uniqueTarget(dir, targetFileNameFor(sourcePath, asName));
    try {
      await File(sourcePath).copy(target.path);
    } on FileSystemException catch (error) {
      throw ExportException('保存失败：${error.message}');
    }
    return SaveResult(outcome: SaveOutcome.directory, detail: target.path);
  }

  /// 逐号试到不存在的文件名：直接覆盖用户已有的同名图片是不可接受的
  File _uniqueTarget(Directory dir, String name) {
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var candidate = File(p.join(dir.path, '$base$ext'));
    var index = 1;
    while (candidate.existsSync()) {
      candidate = File(p.join(dir.path, '$base-$index$ext'));
      index++;
    }
    return candidate;
  }
}

/// 测试用内存实现（记录被保存的源路径与请求的展示名，不触平台通道）
class RecordingImageSaver implements ImageSaver {
  RecordingImageSaver();

  final List<String> saved = <String>[];

  /// 与 [saved] 一一对应的展示名（未指定时为 null）
  final List<String?> requestedNames = <String?>[];

  @override
  Future<SaveResult> save(String sourcePath, {String? asName}) async {
    saved.add(sourcePath);
    requestedNames.add(asName);
    return const SaveResult(outcome: SaveOutcome.gallery, detail: '');
  }
}

/// 按平台挑实现。放在这里而不是 UI 里：调用方不该关心"我现在跑在什么系统上"。
ImageSaver defaultImageSaver() =>
    (Platform.isAndroid || Platform.isIOS)
        ? const GalleryImageSaver()
        : const DesktopImageSaver();
