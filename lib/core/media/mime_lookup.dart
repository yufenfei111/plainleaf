import 'package:path/path.dart' as p;

/// 扩展名 → MIME 的轻量映射（W17 多格式文件支持）
///
/// **为什么不引 `mime` 包**：本阶段 mime 只用于展示与"交给系统打开"的场景，
/// 决定走哪条处理路径靠的是 [AssetKind]（文件头 + 扩展名）。
/// 为这点用途新增一个平台无关的依赖并不划算；将来确需完整映射表时再替换。
///
/// 未收录的扩展名返回 null —— `assets.mimeType` 本就可空，读取端有兜底
/// （按 kind 推断），因此这里可以只覆盖常见类型而不必求全。
String? mimeForFileName(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  if (ext.isEmpty) return null;
  return _byExtension[ext.substring(1)];
}

const Map<String, String> _byExtension = {
  // 图片
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'avif': 'image/avif',
  'svg': 'image/svg+xml',
  // 视频
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'mkv': 'video/x-matroska',
  'webm': 'video/webm',
  'avi': 'video/x-msvideo',
  'm4v': 'video/x-m4v',
  '3gp': 'video/3gpp',
  // 音频
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'flac': 'audio/flac',
  'ogg': 'audio/ogg',
  'opus': 'audio/opus',
  'amr': 'audio/amr',
  // 文档
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'xml': 'application/xml',
  'yaml': 'application/yaml',
  'yml': 'application/yaml',
  'html': 'text/html',
  'epub': 'application/epub+zip',
  // 压缩包
  'zip': 'application/zip',
  'rar': 'application/vnd.rar',
  '7z': 'application/x-7z-compressed',
  'tar': 'application/x-tar',
  'gz': 'application/gzip',
};
