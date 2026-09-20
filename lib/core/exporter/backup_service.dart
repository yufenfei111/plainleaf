import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import '../storage/media_storage.dart';

/// 备份包条目（列表展示用，不触库——恢复后库已关闭仍可安全调用）
class BackupFileInfo {
  const BackupFileInfo({
    required this.file,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final File file;
  final DateTime modifiedAt;
  final int sizeBytes;

  String get fileName => p.basename(file.path);
}

/// 本地备份包导出/恢复（W5，issue #13）
/// 包格式（§4.3）：`<name>.plbk` = zip(plainleaf.sqlite + media/** + manifest.json)
/// manifest 记录 schemaVersion、导出时间与统计；恢复前做完整性校验。
/// 一致性快照用 SQLite 的 VACUUM INTO（sqlite3_flutter_libs 自带 3.27+）。
/// 数据库文件位置 = drift_flutter 默认：ApplicationDocuments/plainleaf.sqlite。
class BackupService {
  BackupService(this._db, {MediaStorage? mediaStorage})
      : _media = mediaStorage ?? MediaStorage();

  final PlainLeafDatabase _db;
  final MediaStorage _media;

  /// drift_flutter 默认库文件（与 connection.dart 的 driftDatabase(name: 'plainleaf') 对应）
  static Future<File> defaultDbFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'plainleaf.sqlite'));
  }

  /// 列出私有目录下的 .plbk（按修改时间倒序）。
  /// M1 形态：恢复入口直接列本地备份，W6 再用 file_selector 支持任意路径选择。
  Future<List<BackupFileInfo>> listBackups() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(docs.path);
    if (!dir.existsSync()) return const [];
    final out = <BackupFileInfo>[];
    await for (final f in dir.list()) {
      if (f is File && p.extension(f.path).toLowerCase() == '.plbk') {
        final stat = await f.stat();
        out.add(BackupFileInfo(
          file: f,
          modifiedAt: stat.modified,
          sizeBytes: stat.size,
        ));
      }
    }
    out.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return out;
  }

  /// 导出 .plbk，返回文件（ApplicationDocuments 下）
  Future<File> exportBackup({String? fileName}) async {
    final tmpDir = await Directory.systemTemp.createTemp('plainleaf_bak');
    try {
      // 1) 一致性数据库快照（不依赖打开连接的文件直拷）
      final snapshotPath = p.join(tmpDir.path, 'plainleaf.sqlite');
      await _db.customStatement('VACUUM INTO ?', [snapshotPath]);
      final snapshot = File(snapshotPath);
      if (!snapshot.existsSync() || snapshot.lengthSync() == 0) {
        throw const FileSystemException('数据库快照生成失败');
      }

      // 2) 收集媒体文件（相对路径用正斜杠，与库内 relPath 约定一致）
      //    只打包 media（原图）与 thumb（缩略图）；medium 是派生图，
      //    体积大而可重算，恢复后按需再生成，避免备份包翻倍。
      final support = await _media.supportDir();
      final archive = Archive();
      final snapshotBytes = snapshot.readAsBytesSync();
      archive.addFile(ArchiveFile('plainleaf.sqlite', snapshotBytes.length, snapshotBytes));
      for (final kind in <MediaKind>[MediaKind.original, MediaKind.thumb]) {
        final root = await _media.root(kind);
        if (!root.existsSync()) continue;
        await for (final f in root.list(recursive: true)) {
          if (f is File) {
            final rel = p.posix.joinAll(
              p.split(p.relative(f.path, from: support.path)),
            );
            final bytes = f.readAsBytesSync();
            archive.addFile(ArchiveFile(rel, bytes.length, bytes));
          }
        }
      }

      // 3) manifest
      final entries = await _db.select(_db.entries).get();
      final manifest = {
        'app': 'plainleaf',
        // format 升到 plbk/2：含 thumb 目录（W6 两级缩略图）；向后兼容 plbk/1
        'format': 'plbk/2',
        'schemaVersion': _db.schemaVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'entries': entries.where((e) => !e.deleted).length,
        'mediaFiles': archive.files.where((f) => f.name.startsWith('media/')).length,
      };
      final manifestBytes =
          utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
      archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

      // 4) 写 zip
      final zipBytes = ZipEncoder().encode(archive) as List<int>;
      final docs = await getApplicationDocumentsDirectory();
      final outName = fileName ??
          'plainleaf-backup-${DateTime.now().toIso8601String().substring(0, 10)}.plbk';
      final out = File(p.join(docs.path, outName));
      await out.writeAsBytes(zipBytes, flush: true);
      return out;
    } finally {
      if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
    }
  }

  /// 校验 .plbk 完整性（manifest + 格式版本 + db 快照存在），返回 manifest
  Future<Map<String, Object?>> verify(File plbk) async {
    final bytes = plbk.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifest = archive.findFile('manifest.json');
    if (manifest == null) {
      throw const FormatException('备份包缺少 manifest.json，无法校验');
    }
    final map =
        jsonDecode(utf8.decode(manifest.content as List<int>)) as Map<String, Object?>;
    // 兼容两代格式：plbk/1（仅原图）与 plbk/2（含 thumb）
    const supported = {'plbk/1', 'plbk/2'};
    if (map['app'] != 'plainleaf' ||
        !supported.contains(map['format'].toString())) {
      throw FormatException('不支持的备份包格式: ${map['format']}');
    }
    if (archive.findFile('plainleaf.sqlite') == null) {
      throw const FormatException('备份包缺少数据库快照');
    }
    return map;
  }

  /// 恢复：校验 → 自动安全备份当前数据 → 关库 → 替换库文件 → 还原媒体。
  /// 返回被替换的库文件路径；恢复完成后需重启应用加载新数据。
  Future<File> restore(File plbk) async {
    await verify(plbk);
    // 数据红线：恢复前自动备份当前数据
    await exportBackup(
        fileName: 'plainleaf-before-restore-${DateTime.now().millisecondsSinceEpoch}.plbk');

    final bytes = plbk.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final dbFile = archive.findFile('plainleaf.sqlite')!;

    final target = await defaultDbFile();
    await _db.close();
    await target.parent.create(recursive: true);
    await target.writeAsBytes(dbFile.content as List<int>, flush: true);

    final support = await _media.supportDir();
    for (final f in archive.files) {
      // 包内相对路径以支持目录为基准（media/…、thumb/…）
      if (f.isFile &&
          (f.name.startsWith('media/') || f.name.startsWith('thumb/'))) {
        final out = File(p.join(support.path, f.name));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>, flush: true);
      }
    }
    return target;
  }
}