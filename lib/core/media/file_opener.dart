import 'package:flutter/services.dart' show MissingPluginException;
import 'package:open_filex/open_filex.dart';

import '../errors/app_exception.dart';

/// 把文件交给系统应用打开（W17 P0-6）
///
/// ## 为什么"交给系统"是这一步最划算的做法
/// 一行代码覆盖所有 B 档格式（Word / Excel / 压缩包 / 任何未知类型），
/// 而且不必自己维护 Office 渲染。内置预览只对确实高频的类型（图片、PDF）
/// 才值得投入 —— 那属于 P1。
///
/// ## 为什么要抽成接口
/// 同 [AttachmentPicker]：平台通道在 `flutter test` 里必抛 `MissingPluginException`，
/// 异常映射与 UI 提示要能进 CI 就必须可替换。
abstract class FileOpener {
  /// 用系统默认应用打开；失败时抛 [PickerException]（消息面向用户）。
  Future<void> open(String absPath);
}

class SystemFileOpener implements FileOpener {
  const SystemFileOpener();

  @override
  Future<void> open(String absPath) async {
    try {
      final result = await OpenFilex.open(absPath);
      switch (result.type) {
        case ResultType.done:
          return;
        case ResultType.noAppToOpen:
          throw const PickerException('这台设备上没有能打开该类型文件的应用');
        case ResultType.fileNotFound:
          throw const PickerException('文件不存在或已被移动');
        case ResultType.permissionDenied:
          throw const PickerException('没有权限打开该文件');
        case ResultType.error:
          throw PickerException('打开失败：${result.message}');
      }
    } on MissingPluginException {
      throw const PickerException('当前环境不支持用系统应用打开文件');
    }
  }
}

/// 测试用实现：只记录被打开的路径，不触平台通道
class RecordingFileOpener implements FileOpener {
  RecordingFileOpener();

  final List<String> opened = <String>[];

  @override
  Future<void> open(String absPath) async => opened.add(absPath);
}

FileOpener defaultFileOpener() => const SystemFileOpener();
