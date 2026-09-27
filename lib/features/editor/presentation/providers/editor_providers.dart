import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/attachment_picker.dart';
import '../../../../core/media/file_opener.dart';

/// 选择本机文件（W17 多格式附件）
///
/// 测试必须 override 成 `ScriptedAttachmentPicker`：默认实现走 `file_picker`
/// 平台通道，在测试宿主里必抛 `MissingPluginException`。
/// 这与 W15 的 `imageSaverProvider` 是同一处理方式。
final attachmentPickerProvider =
    Provider<AttachmentPicker>((ref) => defaultAttachmentPicker());

/// 交给系统应用打开文件（W17 P0-6）
///
/// 测试 override 成 `RecordingFileOpener`，断言"点开文件时把正确路径交了出去"，
/// 而不必真的唤起系统应用。
final fileOpenerProvider =
    Provider<FileOpener>((ref) => defaultFileOpener());
