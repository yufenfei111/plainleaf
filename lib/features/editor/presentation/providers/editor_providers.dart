import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/attachment_picker.dart';

/// 选择本机文件（W17 多格式附件）
///
/// 测试必须 override 成 `ScriptedAttachmentPicker`：默认实现走平台通道，
/// 在测试宿主里必抛 `MissingPluginException`。
/// 这与 W15 的 `imageSaverProvider` 是同一处理方式。
///
/// 注：`fileOpenerProvider`（交给系统打开）W19 起挪到了 `app/providers.dart` ——
/// 详情页的附件区也要用它，能力类 Provider 只应有一处注册。
final attachmentPickerProvider =
    Provider<AttachmentPicker>((ref) => defaultAttachmentPicker());
