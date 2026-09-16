import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/storage/media_storage.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// W4 测试：媒体私有目录存储（§4.3 路径约定）+ 图片附件挂接（issue #7）
void main() {
  // path_provider 桌面测试桩：所有目录指向临时目录
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('plainleaf_w4');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  late PlainLeafDatabase db;
  late LocalTimelineRepository repo;
  late MediaStorage storage;

  setUp(() {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
    storage = MediaStorage();
    repo = LocalTimelineRepository(
      db.entriesDao,
      assetsDao: db.assetsDao,
      mediaStorage: storage,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('importFile：来源图复制进 media/yyyy/mm/，相对路径可解析回原文件', () async {
    final tmp = Directory.systemTemp.createTempSync('plainleaf_src');
    final src = File('${tmp.path}/sample.jpg')
      ..writeAsBytesSync(List.generate(64, (i) => i));

    final rel = await storage.importFile(src.path);
    expect(rel, matches(RegExp(r'^media/\d{4}/\d{2}/[0-9a-f-]{36}\.jpg$')));

    final resolved = await storage.resolve(rel);
    expect(resolved.existsSync(), isTrue);
    expect(resolved.lengthSync(), src.lengthSync());
  });

  test('attachImage → firstImagePath：挂接后首图路径可取', () async {
    final tmp = Directory.systemTemp.createTempSync('plainleaf_src2');
    final src = File('${tmp.path}/p.png')..writeAsBytesSync([1, 2, 3]);

    final entryId = await repo.saveEntry(
        const EntryDraft(title: '带图记录', plainText: '内容'));
    await repo.attachImage(entryId, src.path);

    final rel = await repo.firstImagePath(entryId);
    expect(rel, isNotNull);
    expect(rel, matches(RegExp(r'^media/\d{4}/\d{2}/')));
  });

  test('无图条目 firstImagePath 返回 null；资产软删后同样返回 null', () async {
    final entryId = await repo.saveEntry(
        const EntryDraft(title: '纯文本', plainText: '没有图片'));
    expect(await repo.firstImagePath(entryId), isNull);

    final tmp = Directory.systemTemp.createTempSync('plainleaf_src3');
    final src = File('${tmp.path}/b.jpg')..writeAsBytesSync([9]);
    await repo.attachImage(entryId, src.path);
    final assets = await db.assetsDao.byEntry(entryId);
    await db.assetsDao.softDelete(assets.first.id);

    expect(await repo.firstImagePath(entryId), isNull);
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async =>
      root;
}
