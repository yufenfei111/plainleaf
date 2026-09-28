import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/exporter/markdown_exporter.dart';
import 'package:plainleaf/core/media/asset_kind.dart';
import 'package:plainleaf/core/media/file_opener.dart';
import 'package:plainleaf/core/storage/media_storage.dart';
import 'package:plainleaf/features/detail/presentation/entry_detail_page.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/features/timeline/presentation/timeline_page.dart';
import 'package:plainleaf/main.dart';
import 'package:plainleaf/shared/widgets/asset_thumb.dart';

/// W19：附件展示收口 + 非图片附件的可见性。
///
/// ## 这轮要守住的到底是什么
/// W17 让"任意格式都能导入"，但**导入 ≠ 能看见**。当时留下三个洞：
///   ① 展示层 6 处各写各的 `Image.file`，非图片一律退化成破图占位；
///   ② 时间轴卡片只查首**图**，一条只挂着 PDF 的记录看起来和"没有附件"一模一样；
///   ③ 详情页只列图片，退出编辑后**再也看不到**自己挂了什么文件。
/// 本文件按这三条分别设用例，另加一条导出清单（否则导出成 Markdown
/// 就不知道记录带了什么）。
///
/// ## 为什么这些用例必须存在
/// 这三类问题的共同点是**不会报错**：没有崩溃、没有日志、测试也不红，
/// 只是用户看不见。唯一能挡住它们的手段就是把"看得见"本身写成断言。
void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('plainleaf_w19');
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

  String writeTemp(String name, List<int> bytes) {
    final tmp = Directory.systemTemp.createTempSync('plainleaf_w19_src');
    final file = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  /// 一个只有文件头是真的 PDF（类型探测按文件头走，内容不重要）
  String writePdf([String name = '作业第三章.pdf']) =>
      writeTemp(name, const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37]);

  String writePng(String name) =>
      writeTemp(name, img.encodePng(img.Image(width: 8, height: 8)));

  Future<int> newEntry([String title = '附件可见性']) =>
      repo.saveEntry(EntryDraft(title: title, plainText: '正文'));

  /// 取时间轴里那条记录（走真实的 watchTimeline，而不是绕过查询手拼实体）
  Future<TimelineEntry> timelineEntryOf(int entryId) async {
    final rows = await repo.watchTimeline(limit: 50).first;
    return rows.firstWhere((e) => e.id == entryId);
  }

  // ─────────────────────────────────────────────────────────────────
  // ① 展示层收口的核心策略（纯函数，不必进 Widget 树）
  // ─────────────────────────────────────────────────────────────────
  group('AssetThumb.bitmapFor —— 挑位图来源的唯一决策点', () {
    test('图片：thumb 优先，缺失时回退原图（历史数据没有 thumb）', () {
      expect(
        AssetThumb.bitmapFor(
          kind: AssetKind.image,
          thumbPath: 'thumb/a_t.jpg',
          relPath: 'media/a.jpg',
        ),
        'thumb/a_t.jpg',
      );
      expect(
        AssetThumb.bitmapFor(kind: AssetKind.image, relPath: 'media/a.jpg'),
        'media/a.jpg',
      );
    });

    test('非图片：只认 thumb，绝不把原文件喂给图片解码器', () {
      // PDF 有原文件也没有缩略图（P1 之前）→ 必须返回 null 走类型徽标。
      // 若这里回退原图，Image.file 会把 PDF 二进制交给解码器，
      // 每次重建都稳定抛一次异常 —— 比直接显示图标更糟。
      expect(
        AssetThumb.bitmapFor(kind: AssetKind.pdf, relPath: 'media/a.pdf'),
        isNull,
      );
      expect(
        AssetThumb.bitmapFor(kind: AssetKind.document, relPath: 'media/a.docx'),
        isNull,
      );
      // P1 补上 PDF 首页缩略图后，这里无需改动就会开始渲染
      expect(
        AssetThumb.bitmapFor(
          kind: AssetKind.pdf,
          thumbPath: 'thumb/a_t.jpg',
          relPath: 'media/a.pdf',
        ),
        'thumb/a_t.jpg',
      );
    });

    test('空串与 null 等价：都走类型徽标而不是拼出空路径', () {
      expect(AssetThumb.bitmapFor(kind: AssetKind.image, relPath: ''), isNull);
      expect(AssetThumb.bitmapFor(kind: AssetKind.image), isNull);
    });
  });

  group('徽标文案与文件大小', () {
    test('徽标优先用原始文件名的扩展名（大写）', () {
      expect(assetBadgeLabel(originalName: '作业第三章.pdf'), 'PDF');
      expect(assetBadgeLabel(originalName: '实验报告.docx'), 'DOCX');
    });

    test('拿不到文件名时退到类型中文名（时间轴卡片只有 kind）', () {
      expect(assetBadgeLabel(kind: AssetKind.pdf), 'PDF');
      expect(assetBadgeLabel(kind: AssetKind.document), '文档');
      expect(assetBadgeLabel(kind: AssetKind.archive), '压缩包');
    });

    test('没有扩展名也不留空', () {
      expect(assetBadgeLabel(originalName: 'README', kind: AssetKind.document),
          '文档');
      expect(assetBadgeLabel(), '');
    });

    test('文件大小按 1024 进制、小于 10 留一位小数', () {
      expect(formatFileSize(null), isNull);
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(1023), '1023 B');
      expect(formatFileSize(1024), '1.0 KB');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(1048576), '1.0 MB');
      expect(formatFileSize(345 * 1024 * 1024), '345 MB');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // ② 时间轴聚合：卡片要能知道"带了几个、是什么"
  // ─────────────────────────────────────────────────────────────────
  group('时间轴聚合：附件数量与首个附件类型', () {
    test('只挂 PDF：数量为 1、类型为 pdf、首图为 null（但不能当成"无附件"）', () async {
      final entryId = await newEntry();
      await repo.attachFile(entryId, writePdf());

      final entry = await timelineEntryOf(entryId);
      expect(entry.attachmentCount, 1);
      expect(entry.firstAttachmentKind, AssetKind.pdf);
      expect(entry.hasAttachments, isTrue);
      // 首图仍是 null：卡片因此走类型徽标分支，而不是去渲染一张不存在的图
      expect(entry.firstAssetRelPath, isNull);
    });

    test('混合附件：首图只认图片，数量把非图片一起算上', () async {
      final entryId = await newEntry();
      await repo.attachFile(entryId, writePdf());
      await repo.attachFile(entryId, writePng('照片.png'));

      final entry = await timelineEntryOf(entryId);
      expect(entry.attachmentCount, 2, reason: '数量必须包含非图片附件');
      expect(entry.firstAssetRelPath, isNotNull, reason: '首图应指向那张 PNG');
      expect(entry.firstAssetThumbPath, isNotNull);
      // 首个附件（任意类型）是按 sortIndex 排的 PDF；它与首图**不是同一个文件**，
      // 这正是两个字段必须分开的原因
      expect(entry.firstAttachmentKind, AssetKind.pdf);
    });

    test('无附件：数量 0、首图与首类型都为 null', () async {
      final entryId = await newEntry();
      final entry = await timelineEntryOf(entryId);
      expect(entry.attachmentCount, 0);
      expect(entry.hasAttachments, isFalse);
      expect(entry.firstAttachmentKind, isNull);
    });

    test('软删的附件不计入数量（否则卡片角标会越用越大）', () async {
      final entryId = await newEntry();
      final a = await repo.attachFile(entryId, writePdf('一.pdf'));
      await repo.attachFile(entryId, writePdf('二.pdf'));
      await db.assetsDao.softDelete(a);

      final entry = await timelineEntryOf(entryId);
      expect(entry.attachmentCount, 1);
    });
  });

  group('详情页的两条查询口径（图片 vs 全部）', () {
    test('findAssetsByEntry 只给图片，findAllAssetsByEntry 给全部', () async {
      final entryId = await newEntry();
      await repo.attachFile(entryId, writePdf());
      await repo.attachFile(entryId, writePng('照片.png'));

      final images = await repo.findAssetsByEntry(entryId);
      final all = await repo.findAllAssetsByEntry(entryId);

      expect(images, hasLength(1), reason: '横向翻页只该拿到图片');
      expect(images.single.kind, AssetKind.image);
      expect(all, hasLength(2), reason: '附件区必须看到 PDF');
      // 领域实体要带上展示所需的三件套，否则附件区只能显示 uuid
      final pdf = all.firstWhere((a) => a.kind == AssetKind.pdf);
      expect(pdf.displayName, '作业第三章.pdf');
      expect(pdf.sizeBytes, greaterThan(0));
      expect(pdf.originalName, '作业第三章.pdf');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // ③ 详情页附件区（用户真正"看得见"的地方）
  // ─────────────────────────────────────────────────────────────────
  group('详情页附件区', () {
    testWidgets('挂着 PDF：显示原名与大小，点开交给系统应用', (tester) async {
      final opener = RecordingFileOpener();
      // attachFile 要真复制文件、真写库，必须 runAsync：pump 只推进虚拟时钟，
      // 等不到真实 I/O，直接断言会看到"什么都没发生"。
      final entryId = (await tester.runAsync(() async {
        final id = await newEntry('带 PDF 的记录');
        await repo.attachFile(id, writePdf());
        return id;
      }))!;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbProvider.overrideWithValue(db),
            fileOpenerProvider.overrideWithValue(opener),
          ],
          child: MaterialApp(home: EntryDetailPage(entryId: entryId)),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // ① 附件区出现，且给出**原始文件名**（盘上是 uuid，显示 uuid 等于没显示）
      expect(find.text('作业第三章.pdf'), findsOneWidget,
          reason: '附件区必须显示原始文件名');
      expect(find.textContaining('附件'), findsWidgets);
      // ② 大小也要有："这份是不是我要的那版"靠它判断
      expect(find.text('8 B'), findsOneWidget);
      // ③ PDF 不该被当图片渲染 —— 破图图标说明它被错误地喂给了图片解码器
      expect(find.byIcon(Icons.broken_image), findsNothing);

      // ④ 点开 → 交给系统，且**文件名与列表标题一致**
      //    W20 起交出前会按展示名准备副本（盘上是 uuid，直接交出去系统里就是 uuid）
      await tester.tap(find.text('作业第三章.pdf'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(opener.opened, hasLength(1));
      expect(p.basename(opener.opened.single), '作业第三章.pdf',
          reason: '系统应用里看到的名字必须与列表标题一致');
      expect(File(opener.opened.single).existsSync(), isTrue);

      // drift 的 QueryStream 关闭会排一个 0ms Timer，不推干净会报 pending timer
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('只有图片：不出现附件区（避免与上面的翻页重复罗列）', (tester) async {
      final entryId = (await tester.runAsync(() async {
        final id = await newEntry('只有图片');
        await repo.attachFile(id, writePng('照片.png'));
        return id;
      }))!;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(home: EntryDetailPage(entryId: entryId)),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('照片.png'), findsNothing,
          reason: '图片已经在横向翻页里展示过，附件区不该再列一遍');
      expect(find.textContaining('附件 · '), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // ④ 时间轴卡片：非图片附件也要"看得见"
  // ─────────────────────────────────────────────────────────────────
  group('时间轴卡片', () {
    testWidgets('只挂 PDF 的记录：卡片显示 PDF 图标而不是记录类型图标', (tester) async {
      final entryId = (await tester.runAsync(() async {
        final id = await newEntry('论文材料');
        await repo.attachFile(id, writePdf());
        return id;
      }))!;
      expect(entryId, greaterThan(0));

      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const TimelinePage())],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: PlainLeafApp(routerConfig: router),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget,
          reason: '卡片必须告诉用户"这条记录挂着 PDF"');
      // 这条记录是 note 类型；如果落到旧的"记录类型图标"分支就会是这个
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('多附件显示数量角标；单个附件不显示（避免噪声）', (tester) async {
      final ids = (await tester.runAsync(() async {
        final single = await newEntry('一个附件');
        await repo.attachFile(single, writePdf('a.pdf'));
        final many = await newEntry('三个附件');
        await repo.attachFile(many, writePdf('x.pdf'));
        await repo.attachFile(many, writePdf('y.pdf'));
        await repo.attachFile(many, writePdf('z.pdf'));
        return [single, many];
      }))!;
      expect(ids, hasLength(2));

      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const TimelinePage())],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: PlainLeafApp(routerConfig: router),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('3'), findsOneWidget, reason: '三个附件应显示角标 3');
      expect(find.text('1'), findsNothing,
          reason: '单个附件不显示角标 —— 缩略图本身已经说明了它的存在');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // ⑤ 导出：清单里必须有附件，否则导出就丢了信息
  // ─────────────────────────────────────────────────────────────────
  group('Markdown 导出附件清单（W5 起注释与实现不符的债务）', () {
    test('单条导出：清单带类型、原始文件名与相对路径', () async {
      final entryId = await newEntry('导出验收');
      final assetId = await repo.attachFile(entryId, writePdf());
      final asset = await (db.select(db.assets)
            ..where((a) => a.id.equals(assetId)))
          .getSingle();

      final md = await MarkdownExporter(db).exportEntry(entryId);
      expect(md, contains('## 附件'));
      expect(md, contains('[PDF] 作业第三章.pdf'));
      expect(md, contains(asset.relPath),
          reason: '相对路径是给脚本用的：能据此从备份包里把文件捞回来');
    });

    test('全部导出：附件跟着各自的记录走，不串行', () async {
      final a = await newEntry('有附件');
      await repo.attachFile(a, writePdf('甲.pdf'));
      await newEntry('没附件');

      final md = await MarkdownExporter(db).exportAll();
      expect(md, contains('[PDF] 甲.pdf'));
      // 只有一条记录带附件 → 清单只出现一次
      expect('## 附件'.allMatches(md).length, 1);
    });

    test('无附件时完全不写附件段落（不留空标题）', () async {
      final entryId = await newEntry('干净记录');
      final md = await MarkdownExporter(db).exportEntry(entryId);
      expect(md, isNot(contains('## 附件')));
    });
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  /// W20：交给系统前会按展示名在临时目录准备副本
  @override
  Future<String?> getTemporaryPath() async => root;
}
