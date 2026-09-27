import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/exporter/backup_service.dart';
import 'package:plainleaf/core/exporter/markdown_exporter.dart';
import 'package:plainleaf/core/storage/media_storage.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// W17 P0-7：多格式附件在**备份 / 恢复 / 导出**链路上的回归。
///
/// 预期是"几乎免费"—— `BackupService` 整目录打包 `media/` + `thumb/`、
/// 不枚举文件类型，所以非图片附件理论上会自动被带上。
/// 但**必须实测**：「理论上自动兼容」和「确实在包里」是两件事，
/// 而这类"看起来免费"的地方正是最容易悄悄断掉的地方（恢复出来才发现附件全丢）。
final Directory _root = Directory.systemTemp.createTempSync('plainleaf_w17_bk');

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePaths(_root.path);
  });

  LocalTimelineRepository newRepo(PlainLeafDatabase db) =>
      LocalTimelineRepository(
        db.entriesDao,
        assetsDao: db.assetsDao,
        mediaStorage: MediaStorage(),
      );

  String writeTemp(String name, List<int> bytes) {
    final tmp = Directory.systemTemp.createTempSync('plainleaf_w17_bk_src');
    final file = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  test('① 非图片附件随备份包一起走（解包断言，不靠推断）', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = newRepo(db);
    final entryId =
        await repo.saveEntry(const EntryDraft(title: '带附件的记录', plainText: '正文'));
    await repo.attachFile(
      entryId,
      writeTemp('作业第三章.pdf', const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]),
    );

    final plbk = await BackupService(db).exportBackup(fileName: 'w17-plain.plbk');
    final archive = ZipDecoder().decodeBytes(plbk.readAsBytesSync());
    final names = archive.files.map((f) => f.name).toList();

    expect(
      names.any((n) => n.startsWith('media/') && n.endsWith('.pdf')),
      isTrue,
      reason: '非图片附件必须随包走 —— 否则恢复出来是断链，用户当场就丢文件',
    );
    expect(names.contains('plainleaf.sqlite'), isTrue);
    expect(names.contains('manifest.json'), isTrue);
  });

  test('② 恢复后：资产记录（kind / 原名）与文件本体都回来', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = newRepo(db);
    final entryId =
        await repo.saveEntry(const EntryDraft(title: '待恢复的附件', plainText: '正文'));
    await repo.attachFile(
      entryId,
      writeTemp('实验报告.docx', const [0x50, 0x4B, 0x03, 0x04, 0x00]),
    );

    final service = BackupService(db);
    final plbk = await service.exportBackup(fileName: 'w17-restore.plbk');
    final restored = await service.restore(plbk);

    final db2 = PlainLeafDatabase.forTesting(NativeDatabase(restored));
    addTearDown(db2.close);
    final assets = await db2.assetsDao.allByEntry(entryId);

    expect(assets, hasLength(1));
    expect(assets.first.kind, 'document',
        reason: '类型判断要能从备份里原样回来，否则恢复后附件退化成"未知"');
    expect(assets.first.originalName, '实验报告.docx');
    // 文件本体也要在（BackupService 会还原 media/ 与 thumb/）
    final resolved = await MediaStorage().resolve(assets.first.relPath);
    expect(resolved.existsSync(), isTrue, reason: '恢复后文件本体必须在磁盘上');
  });

  test('③ 加密包同样带上非图片附件（与明文包走同一条打包路径）', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = newRepo(db);
    final entryId =
        await repo.saveEntry(const EntryDraft(title: '加密附件', plainText: '正文'));
    await repo.attachFile(
      entryId,
      writeTemp('一页说明.pdf', const [0x25, 0x50, 0x44, 0x46]),
    );

    final service = BackupService(db);
    final plbk =
        await service.exportBackup(fileName: 'w17-enc.plbk', password: 'pwd-1');
    final restored = await service.restore(plbk, password: 'pwd-1');

    final db2 = PlainLeafDatabase.forTesting(NativeDatabase(restored));
    addTearDown(db2.close);
    final assets = await db2.assetsDao.allByEntry(entryId);
    expect(assets, hasLength(1));
    expect(assets.first.kind, 'pdf');
    final resolved = await MediaStorage().resolve(assets.first.relPath);
    expect(resolved.existsSync(), isTrue);
  });

  test('④ Markdown 导出不因非图片附件而失败（当前不含附件清单，属既有缺口）', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = newRepo(db);
    final entryId =
        await repo.saveEntry(const EntryDraft(title: '导出验收', plainText: '正文内容'));
    await repo.attachFile(
      entryId,
      writeTemp('文件.pdf', const [0x25, 0x50, 0x44, 0x46]),
    );

    final md = await MarkdownExporter(db).exportEntry(entryId);
    // 这里**只断言导出不崩**：`MarkdownExporter._render` 目前根本不写附件段落
    // （类注释写着"图片附件以附件清单形式列出"，但实现里没有 —— 这是既有缺口，
    // 与 W17 无关，已记入记忆，避免把"本该有"误读成"W17 弄丢了"）。
    expect(md, contains('# 导出验收'));
    expect(md, contains('正文内容'));
  });
}

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
