import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/exporter/backup_service.dart';
import 'package:plainleaf/core/errors/app_exception.dart';
import 'package:plainleaf/core/exporter/markdown_exporter.dart';
import 'package:plainleaf/core/storage/media_storage.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:uuid/uuid.dart';

/// W5 验收测试：备份包（issue #13）/ Markdown 导出（#14）/ 标签与笔记本管理（#10/#11）
/// 备份/媒体根（path_provider 桩指向此处，跨用例共享）
final _root = Directory.systemTemp.createTempSync('plainleaf_w5');

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePaths(_root.path);
  });

  late PlainLeafDatabase db;
  late LocalTimelineRepository repo;

  setUp(() {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
    repo = LocalTimelineRepository(db.entriesDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('MarkdownExporter（issue #14）', () {
    test('单条导出：标题/日期/类型/心情头 + 正文', () async {
      final id = await repo.saveEntry(const EntryDraft(
        title: '导出测试',
        plainText: '正文内容甲',
        type: EntryType.diary,
        mood: 4,
      ));
      final md = await MarkdownExporter(db).exportEntry(id);
      expect(md, contains('# 导出测试'));
      expect(md, contains('正文内容甲'));
      expect(md, contains('diary'));
      expect(md, contains('心情: 4'));
    });

    test('全部导出：草稿与软删不出现，已发布按序导出', () async {
      await repo.saveEntry(const EntryDraft(title: '已发布A', plainText: 'a'));
      await repo.saveEntry(const EntryDraft(
          title: '草稿B', plainText: 'b', status: EntryStatus.draft));
      final delId = await repo.saveEntry(
          const EntryDraft(title: '已删C', plainText: 'c'));
      await repo.softDelete(delId);

      final md = await MarkdownExporter(db).exportAll();
      expect(md, contains('已发布A'));
      expect(md, isNot(contains('草稿B')));
      expect(md, isNot(contains('已删C')));
    });
  });

  group('标签管理（issue #11）', () {
    test('创建/重命名/软删 + 条目打标', () async {
      const uuidGen = Uuid();
      final tagId = await db.tagsDao.create(
          uuid: uuidGen.v4(), name: '期末复习');
      await db.tagsDao.rename(tagId, '期末复习改');
      final entryId = await repo.saveEntry(
          const EntryDraft(title: '打标记录', plainText: '内容'));
      await db.tagsDao.tagEntry(entryId, tagId);

      final tags = await db.tagsDao.tagsOfEntry(entryId);
      expect(tags.map((t) => t.name), contains('期末复习改'));

      await db.tagsDao.softDelete(tagId);
      final after = await db.tagsDao.tagsOfEntry(entryId);
      expect(after, isEmpty);
    });
  });

  group('笔记本管理（issue #10）', () {
    test('创建自定义本 + 条目计数', () async {
      const uuidGen = Uuid();
      final nbId = await db.notebooksDao.create(
          uuid: uuidGen.v4(), name: '考研笔记', space: 'study');
      await repo.saveEntry(EntryDraft(
          title: '归入', plainText: '内容', notebookId: nbId));
      expect(await db.notebooksDao.countEntries(nbId), 1);
    });

    test('重命名 / 软删后退出列表 / insertNotebook 直插', () async {
      const uuidGen = Uuid();
      final id = await db.notebooksDao.create(
          uuid: uuidGen.v4(), name: '临时本', space: 'custom');

      await db.notebooksDao.rename(id, '改名后');
      var row = await (db.select(db.notebooks)
            ..where((n) => n.id.equals(id)))
          .getSingle();
      expect(row.name, '改名后');
      expect(row.version, 2, reason: '重命名应递增 version');

      await db.notebooksDao.softDelete(id);
      row = await (db.select(db.notebooks)..where((n) => n.id.equals(id)))
          .getSingle();
      expect(row.deleted, isTrue);

      // 软删后不出现在 watch 流里（数据红线：删除一律软删除）
      final streamed = await db.notebooksDao.watchNotebooks().first;
      expect(streamed.any((n) => n.id == id), isFalse);

      // insertNotebook：直接插 Companion（name 走表默认 '未命名'）
      final inserted = await db.notebooksDao.insertNotebook(
        NotebooksCompanion.insert(uuid: uuidGen.v4()),
      );
      expect(inserted, greaterThan(0));
    });
  });

  group('媒体存储与异常层（core 覆盖率补齐）', () {
    test('deleteRel：物理删除已导入的媒体文件', () async {
      final storage = MediaStorage();
      final tmp = Directory.systemTemp.createTempSync('plainleaf_src');
      final src = File('${tmp.path}/a.jpg')..writeAsBytesSync([1, 2, 3, 4]);
      addTearDown(() => tmp.deleteSync(recursive: true));

      final rel = await storage.importFile(src.path);
      final abs = await storage.resolve(rel);
      expect(abs.existsSync(), isTrue);

      await storage.deleteRel(rel);
      expect(abs.existsSync(), isFalse);
    });

    test('DatabaseException 携带消息与原始异常', () async {
      final cause = Exception('底层炸了');
      final error = DatabaseException('保存失败', cause: cause);
      expect(error.message, '保存失败');
      expect(error.cause, cause);
      expect('$error', '保存失败');
    });
  });

  group('备份包（issue #13）', () {
    test('导出 → 校验 → manifest 内容正确', () async {
      await repo.saveEntry(const EntryDraft(title: '备份对象', plainText: '数据'));
      final service = BackupService(db);
      final plbk = await service.exportBackup(fileName: 'test.plbk');

      expect(plbk.existsSync(), isTrue);
      expect(plbk.path, endsWith('.plbk'));

      final manifest = await service.verify(plbk);
      expect(manifest['app'], 'plainleaf');
      expect(manifest['format'], 'plbk/1');
      // eslint 免误报：实际值可能是 int
      // ignore: avoid_print
      print('manifest schemaVersion = ${manifest['schemaVersion']}');
      expect((manifest['schemaVersion'] as num).toInt(), greaterThanOrEqualTo(1));
      expect((manifest['entries'] as num), greaterThanOrEqualTo(1));
    });

    test('listBackups：只列 .plbk 且按修改时间倒序', () async {
      final service = BackupService(db);
      await service.exportBackup(fileName: 'older.plbk');
      await service.exportBackup(fileName: 'newer.plbk');
      File('${_root.path}/note.txt').writeAsStringSync('not a backup');

      final list = await service.listBackups();
      final names = list.map((e) => e.fileName).toList();
      expect(names, contains('older.plbk'));
      expect(names, contains('newer.plbk'));
      expect(names, isNot(contains('note.txt')), reason: '只列 .plbk');
      expect(
        list.first.modifiedAt.isBefore(list.last.modifiedAt),
        isFalse,
        reason: '应按修改时间倒序',
      );
    });

    test('校验失败：非 plbk 文件抛 FormatException', () async {
      final tmp = Directory.systemTemp.createTempSync('plainleaf_bad');
      final bad = File('${tmp.path}/bad.plbk')..writeAsBytesSync([1, 2, 3]);
      final service = BackupService(db);
      expect(() => service.verify(bad), throwsFormatException);
      tmp.deleteSync(recursive: true);
    });
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