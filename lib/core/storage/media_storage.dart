import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 媒体文件存储（core/storage）：原图存私有目录 `media/yyyy/mm/<uuid>.jpg`
/// 路径约定见 DEVELOPMENT.md §4.3；数据库只存相对路径（relPath）。
/// 压缩 / thumb / medium 两级缩略图在 W6 相册阶段补全（修订版排期）。
class MediaStorage {
  MediaStorage();

  Directory? _mediaRoot;

  /// 媒体根目录（App 支持目录/media）；惰性初始化
  Future<Directory> mediaRoot() async {
    if (_mediaRoot != null) return _mediaRoot!;
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'media'));
    if (!root.existsSync()) root.createSync(recursive: true);
    _mediaRoot = root;
    return root;
  }

  /// 把来源文件复制进私有目录，返回相对路径（media/yyyy/mm/uuid.ext）
  Future<String> importFile(String sourcePath, {DateTime? at}) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw FileSystemException('来源文件不存在', sourcePath);
    }
    final now = at ?? DateTime.now();
    final rel = p.posix.join(
      'media',
      '${now.year}',
      now.month.toString().padLeft(2, '0'),
      '${const Uuid().v4()}${p.extension(sourcePath)}',
    );
    final root = await mediaRoot();
    final target = File(p.join(root.path, rel));
    target.parent.createSync(recursive: true);
    await source.copy(target.path);
    return rel;
  }

  /// 相对路径 → 绝对文件
  Future<File> resolve(String relPath) async {
    final root = await mediaRoot();
    return File(p.join(root.path, relPath));
  }

  /// 物理删除（仅回收站 30 天清理与孤儿清理调用；软删除不动文件）
  Future<void> deleteRel(String relPath) async {
    final root = await mediaRoot();
    final f = File(p.join(root.path, relPath));
    if (f.existsSync()) await f.delete();
  }
}