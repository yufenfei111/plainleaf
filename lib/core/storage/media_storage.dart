import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 媒体文件种类（§4.3）：原图 media/ · 缩略图 thumb/ · 中号图 medium/
/// 三级目录平级放在 App 支持目录下。
enum MediaKind { original, thumb, medium }

/// 媒体文件存储（core/storage）
/// 路径约定见 DEVELOPMENT.md §4.3；数据库只存相对路径（relPath）。
///
/// **相对路径的基准是 App 支持目录**，即 relPath 形如
/// `media/2026/09/{uuid}.jpg`、`thumb/2026/09/{uuid}_t.jpg`。
/// 这样同一字段能同时表达"哪一级 + 哪个月"，解析只需 join 支持目录，
/// 不必为三种类型各存一份字段；W4 落库的旧数据格式也完全兼容。
class MediaStorage {
  MediaStorage();

  Directory? _supportDir;
  final Map<MediaKind, Directory> _roots = {};

  /// App 支持目录（惰性）
  Future<Directory> supportDir() async {
    if (_supportDir != null) return _supportDir!;
    _supportDir = await getApplicationSupportDirectory();
    return _supportDir!;
  }

  /// 各级根目录（惰性创建）：media / thumb / medium
  Future<Directory> root(MediaKind kind) async {
    final cached = _roots[kind];
    if (cached != null) return cached;
    final name = switch (kind) {
      MediaKind.original => 'media',
      MediaKind.thumb => 'thumb',
      MediaKind.medium => 'medium',
    };
    final support = await supportDir();
    final dir = Directory(p.join(support.path, name));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _roots[kind] = dir;
    return dir;
  }

  /// 媒体根目录（App 支持目录/media）；惰性初始化
  Future<Directory> mediaRoot() => root(MediaKind.original);

  /// 相对路径 → 绝对文件（基准：支持目录）
  Future<File> resolve(String relPath) async {
    final support = await supportDir();
    return File(p.join(support.path, relPath));
  }

  /// 在指定级别下生成一个新的相对路径（yyyy/mm/{name}{ext}）
  String newRelPath(MediaKind kind, String name, String ext, {DateTime? at}) {
    final now = at ?? DateTime.now();
    return p.posix.join(
      switch (kind) {
        MediaKind.original => 'media',
        MediaKind.thumb => 'thumb',
        MediaKind.medium => 'medium',
      },
      '${now.year}',
      now.month.toString().padLeft(2, '0'),
      '$name$ext',
    );
  }

  /// 把来源文件复制进私有目录，返回相对路径（media/yyyy/mm/uuid.ext）
  Future<String> importFile(String sourcePath, {DateTime? at}) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw FileSystemException('来源文件不存在', sourcePath);
    }
    final rel = newRelPath(
      MediaKind.original,
      const Uuid().v4(),
      p.extension(sourcePath),
      at: at,
    );
    final target = await resolve(rel);
    target.parent.createSync(recursive: true);
    await source.copy(target.path);
    return rel;
  }

  /// 物理删除（仅回收站 30 天清理与孤儿清理调用；软删除不动文件）
  Future<void> deleteRel(String relPath) async {
    final f = await resolve(relPath);
    if (f.existsSync()) await f.delete();
  }
}
