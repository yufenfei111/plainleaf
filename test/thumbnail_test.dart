import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/media/thumbnail_pipeline.dart';
import 'package:plainleaf/core/storage/media_storage.dart';
import 'package:plainleaf/features/gallery/data/gallery_repository_impl.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:uuid/uuid.dart';

/// W6 图片管线验收：两级缩略图 / Isolate 转码 / 回填 / 分页
final _root = Directory.systemTemp.createTempSync('plainleaf_thumb');

/// 造一张指定尺寸的测试图（纯色填充，避免噪点影响编码体积断言）
List<int> _makeJpg(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(120, 180, 90));
  return img.encodeJpg(image, quality: 95);
}

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePaths(_root.path);
  });

  group('ThumbnailPipeline（§4.3 + §5.2 Isolate 红线）', () {
    test('大图：thumb 长边 400、medium 不放大，并回填宽高与 sha256', () async {
      final dir = Directory.systemTemp.createTempSync('pl_pipe');
      addTearDown(() => dir.deleteSync(recursive: true));
      final src = File(p.join(dir.path, 'src.jpg'))
        ..writeAsBytesSync(_makeJpg(1600, 1200));

      final derived = await ThumbnailPipeline().generate(
        sourceAbs: src.path,
        thumbAbs: p.join(dir.path, 't.jpg'),
        mediumAbs: p.join(dir.path, 'm.jpg'),
        thumbRel: 'thumb/t.jpg',
        mediumRel: 'medium/m.jpg',
      );

      expect(derived.width, 1600);
      expect(derived.height, 1200);
      expect(derived.sizeBytes, greaterThan(0));
      expect(derived.hashSha256, hasLength(64));

      final thumb = img.decodeImage(File(p.join(dir.path, 't.jpg')).readAsBytesSync());
      expect(thumb, isNotNull);
      expect(thumb!.width, ThumbnailPipeline.thumbLongEdge);

      final medium = img.decodeImage(File(p.join(dir.path, 'm.jpg')).readAsBytesSync());
      expect(medium, isNotNull);
      // 原图长边已等于 medium 目标边 → 不放大
      expect(medium!.width, 1600);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('小图不放大（避免插值变糊、白耗 IO）', () async {
      final dir = Directory.systemTemp.createTempSync('pl_pipe_small');
      addTearDown(() => dir.deleteSync(recursive: true));
      final src = File(p.join(dir.path, 'src.jpg'))
        ..writeAsBytesSync(_makeJpg(200, 150));

      await ThumbnailPipeline().generate(
        sourceAbs: src.path,
        thumbAbs: p.join(dir.path, 't.jpg'),
        mediumAbs: p.join(dir.path, 'm.jpg'),
        thumbRel: 'thumb/t.jpg',
        mediumRel: 'medium/m.jpg',
      );

      final thumb = img.decodeImage(File(p.join(dir.path, 't.jpg')).readAsBytesSync());
      expect(thumb!.width, 200, reason: '小于目标边时应保持原尺寸');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('attachImage 与相册分页（issue W6）', () {
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

    test('挂接图片：生成两级缩略图并回填元信息', () async {
      final src = File(p.join(_root.path, 'src_${const Uuid().v4()}.jpg'))
        ..writeAsBytesSync(_makeJpg(1200, 900));
      final entryId = await repo.saveEntry(
          const EntryDraft(title: '带图记录', plainText: '内容'));
      final assetId = await repo.attachImage(entryId, src.path);

      final rows = await db.assetsDao.byEntry(entryId);
      final a = rows.firstWhere((x) => x.id == assetId);
      expect(a.thumbPath, isNotNull);
      expect(a.mediumPath, isNotNull);
      expect(a.width, 1200);
      expect(a.height, 900);
      expect(a.hashSha256, isNotNull);

      // 缩略图确实落到了 thumb/ 下（相对路径以支持目录为基准）
      final thumbFile = await storage.resolve(a.thumbPath!);
      expect(thumbFile.existsSync(), isTrue);
      expect(a.thumbPath, startsWith('thumb/'));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('backfillDerived：补齐历史资产（W4 期没 thumb 的图）', () async {
      // 模拟历史数据：直接 attach，不带派生字段
      final entryId = await repo.saveEntry(
          const EntryDraft(title: '历史记录', plainText: '内容'));
      final rel = await storage.importFile(
        (File(p.join(_root.path, 'legacy_${const Uuid().v4()}.jpg'))
          ..writeAsBytesSync(_makeJpg(800, 600)))
            .path,
      );
      final legacyId = await db.assetsDao.attach(
        uuid: const Uuid().v4(),
        entryId: entryId,
        kind: 'image',
        relPath: rel,
      );
      expect((await db.assetsDao.missingThumb()).map((a) => a.id),
          contains(legacyId));

      final done = await repo.backfillDerived();
      expect(done, greaterThanOrEqualTo(1));

      final after = await db.assetsDao.missingThumb();
      expect(after.map((a) => a.id), isNot(contains(legacyId)));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('相册分页：count 与 page 一致', () async {
      final entryId = await repo.saveEntry(
          const EntryDraft(title: '带图', plainText: '内容'));
      final src = File(p.join(_root.path, 'album_${const Uuid().v4()}.jpg'))
        ..writeAsBytesSync(_makeJpg(600, 400));
      await repo.attachImage(entryId, src.path);

      final gallery = LocalGalleryRepository(db.assetsDao);
      expect(await gallery.count(), 1);
      final page = await gallery.page(limit: 10, offset: 0);
      expect(page.length, 1);
      expect(page.first.thumbPath, isNotNull);

      // 越界页返回空
      expect(await gallery.page(limit: 10, offset: 10), isEmpty);
    }, timeout: const Timeout(Duration(seconds: 60)));
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
