import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show MissingPluginException;

import '../errors/app_exception.dart';

/// 用户选中的本机文件（只带挂接所需的最小信息）
class PickedAttachment {
  const PickedAttachment({required this.path, this.name});

  /// 来源文件的绝对路径（系统选择器给的临时路径，随时可能被清理）
  final String path;

  /// 原始文件名。`file_picker` 在部分平台不给 name，此时调用方应回退到
  /// 路径的 basename —— 非图片文件必须能看到原名，否则列表里只剩 uuid。
  final String? name;
}

/// 从本机选择任意类型的文件（W17 多格式附件）
///
/// ## 为什么要抽成接口
/// `file_picker` 走平台通道，`flutter test` 里调用必抛 `MissingPluginException`。
/// 选择流程（取消、异常映射、回调后的状态更新）要能进 CI，就必须能把实现换掉 ——
/// 与 W15 的 `ImageSaver` 是同一个理由与同一种做法。
abstract class AttachmentPicker {
  /// 选择文件；**用户取消时返回 null**（不是异常 —— 取消是正常操作）。
  Future<PickedAttachment?> pickFile();
}

/// `file_selector` 实现（Flutter 官方包）
///
/// 选它而不是 `file_picker` 的原因见 pubspec 里的注释（AGP 9 与 win32 双重堵死）。
/// 有一点很关键：**Android 上它返回的是真实文件路径** —— 原生侧会把选中的文件
/// 复制到 `{cacheDir}/{uuid}/{原文件名}` 再回传（见其 `FileUtils`），
/// 所以可以直接 `File(path)` 读它、复制进私有目录；同时文件名也保留了原名。
class SystemAttachmentPicker implements AttachmentPicker {
  const SystemAttachmentPicker();

  @override
  Future<PickedAttachment?> pickFile() async {
    try {
      // 不做类型过滤：本阶段的契约就是"任何文件都能选、都能记进来"。
      final picked = await openFile();
      if (picked == null) return null; // 用户取消
      return PickedAttachment(path: picked.path, name: picked.name);
    } on MissingPluginException {
      // 宿主没注册插件（或跑在测试宿主里）：归成"当前环境不支持"，
      // 而不是把一个 MissingPluginException 甩给用户
      throw const PickerException('当前环境不支持选择文件');
    }
  }
}

/// 测试用实现：按预设脚本依次返回，不触平台通道。
/// 脚本用尽后返回 null，等价于"用户又点了取消"。
class ScriptedAttachmentPicker implements AttachmentPicker {
  ScriptedAttachmentPicker(this.script);

  /// 每一项代表一次 pickFile 的返回值（null = 用户取消）
  final List<PickedAttachment?> script;

  /// 记录被调用的次数，便于断言"取消时不应挂接"
  int callCount = 0;

  @override
  Future<PickedAttachment?> pickFile() async {
    callCount++;
    if (script.isEmpty) return null;
    return script.removeAt(0);
  }
}

/// 按平台挑实现。目前只有一种（系统选择器三端通用），
/// 保留工厂是为了与 `defaultImageSaver()` 一致，将来分平台时不必改调用点。
AttachmentPicker defaultAttachmentPicker() => const SystemAttachmentPicker();
