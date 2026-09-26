import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/errors/app_exception.dart';
import 'package:plainleaf/core/storage/media_storage.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// W17 P0-3：attachFile 挂接**任意类型**文件。
///
/// 这组用例守住四条：
///   ① 非图片也能落库，且 kind / mime / **原始文件名** 都写对
///   ② 非图片不生成缩略图（thumbPath 为 null 是合法状态，不是失败）
///   ③ 未知格式不抛异常 —— 契约是「任何文件都能记进来」
///   ④ 改造没有破坏原来的图片路径（仍有两级缩略图）
void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('plainleaf_w17');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  late PlainLeafDatabase db;
  late LocalTimelineRepository repo;

  setUp(() {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
    repo = LocalTimelineRepository(
      db.entriesDao,
      assetsDao: db.assetsDao,
      mediaStorage: MediaStorage(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 把一段字节写进临时文件并返回路径（文件名参与类型探测，所以必须保留）
  String writeTemp(String name, List<int> bytes) {
    final tmp = Directory.systemTemp.createTempSync('plainleaf_w17_src');
    final file = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  Future<int> newEntry() =>
      repo.saveEntry(const EntryDraft(title: '附件测试', plainText: '正文'));

  Future<Asset> reload(int assetId) => (db.select(db.assets)
        ..where((a) => a.id.equals(assetId)))
      .getSingle();

  test('挂接 PDF：kind / mime / 原始文件名正确，且不生成缩略图', () async {
    final path = writeTemp(
        '作业第三章.pdf', [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37]);
    final entryId = await newEntry();
    final assetId = await repo.attachFile(entryId, path);
    final asset = await reload(assetId);

    expect(asset.kind, 'pdf');
    expect(asset.mimeType, 'application/pdf');
    expect(asset.originalName, '作业第三章.pdf');
    expect(asset.sizeBytes, greaterThan(0));
    // P0 阶段只对图片生成缩略图；PDF 首页缩略图属 P1
    expect(asset.thumbPath, isNull);
    expect(asset.mediumPath, isNull);
    // 原文件确实落地了
    final resolved = await MediaStorage().resolve(asset.relPath);
    expect(resolved.existsSync(), isTrue);
  });

  test('挂接 docx：落盘名是 uuid，但原名可读（这是非图片的关键体验）', () async {
    final path = writeTemp('实验报告.docx', [0x50, 0x4B, 0x03, 0x04, 0x00]);
    final entryId = await newEntry();
    final assetId = await repo.attachFile(entryId, path);
    final asset = await reload(assetId);

    expect(asset.kind, 'document');
    expect(asset.originalName, '实验报告.docx');
    // 文件名与扩展名都要对：落盘用 uuid（去重、避免路径注入），原名只作展示
    expect(asset.relPath, isNot(contains('实验报告')));
    expect(asset.relPath, endsWith('.docx'));
  });

  test('挂接未知格式：落 other 且不抛异常（「任何文件都能记进来」是契约）', () async {
    final path = writeTemp('mystery.xyzabc', [0x01, 0x02, 0x03, 0x04]);
    final entryId = await newEntry();
    final assetId = await repo.attachFile(entryId, path);
    final asset = await reload(assetId);

    expect(asset.kind, 'other');
    expect(asset.originalName, 'mystery.xyzabc');
    // 未收录的扩展名没有 mime —— 字段可空是设计的一部分，读取端按 kind 兜底
    expect(asset.mimeType, isNull);
    expect(asset.thumbPath, isNull);
  });

  test('扩展名会骗人：图片内容存成 .pdf，仍按文件头判为 image', () async {
    final png = img.encodePng(img.Image(width: 4, height: 4));
    final path = writeTemp('伪装.pdf', png);
    final entryId = await newEntry();
    final assetId = await repo.attachFile(entryId, path);
    final asset = await reload(assetId);

    expect(asset.kind, 'image');
    // 能解码，所以应该有缩略图
    expect(asset.thumbPath, isNotNull);
  });

  test('挂接图片：两级缩略图与宽高照旧（改造没破坏原路径）', () async {
    final png = img.encodePng(img.Image(width: 8, height: 6));
    final path = writeTemp('photo.png', png);
    final entryId = await newEntry();
    final assetId = await repo.attachFile(entryId, path);
    final asset = await reload(assetId);

    expect(asset.kind, 'image');
    expect(asset.mimeType, 'image/png');
    expect(asset.originalName, 'photo.png');
    expect(asset.thumbPath, isNotNull);
    expect(asset.mediumPath, isNotNull);
    expect(asset.width, 8);
    expect(asset.height, 6);
  });

  test('来源文件不存在：抛 DatabaseException，不静默吞掉', () async {
    final entryId = await newEntry();
    await expectLater(
      repo.attachFile(entryId, '/no/such/path/报告.pdf'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('同一类型多次挂接互不干扰（各自 uuid 落盘）', () async {
    final entryId = await newEntry();
    final a = writeTemp('一.pdf', [0x25, 0x50, 0x44, 0x46]);
    final b = writeTemp('二.pdf', [0x25, 0x50, 0x44, 0x46]);
    final idA = await repo.attachFile(entryId, a);
    final idB = await repo.attachFile(entryId, b);

    final assetA = await reload(idA);
    final assetB = await reload(idB);
    expect(assetA.relPath, isNot(assetB.relPath));
    expect(assetA.originalName, '一.pdf');
    expect(assetB.originalName, '二.pdf');
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
