import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/media/asset_kind.dart';
import 'package:plainleaf/core/storage/media_storage.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_filter.dart';
import 'package:plainleaf/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:plainleaf/features/timeline/presentation/timeline_page.dart';
import 'package:plainleaf/main.dart';
import 'package:plainleaf/shared/widgets/asset_thumb.dart';

/// W20 · P1-9 音频封面与时长 + P1-10 按附件类型筛选
///
/// ## 为什么这两项排在本阶段
/// `plan-multiformat-assets.md` 的 P1 三项里，PDF 首页缩略图（P1-8）需要平台
/// 通道依赖（pdfx 在 Windows 还要改 CMakeLists 引 PDFium，且 AGP 9 兼容性未知），
/// 而这两项**可以完全在本机验完**：音频元信息是纯 Dart 解析，
/// 附件类型筛选是 SQL where + 筛选 UI。
///
/// ## 守住什么
///   ① 音频时长落进 `durationMs`（字段 W4 建表就预留了）
///   ② 内嵌封面走缩略图管线，**但不能把封面的尺寸/字节数写进音频资产**
///      —— 那会让"文件大小"这一栏变成谎话
///   ③ 读不出元信息绝不影响挂接（契约：任何文件都能记进来）
///   ④ 按附件类型筛选语义是「**含**该类」，且必须下推 SQL
///      （客户端筛选会被 LIMIT 先截断，得到"几乎没有"的假象）
void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('plainleaf_w20_av');
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
    final tmp = Directory.systemTemp.createTempSync('plainleaf_w20_av_src');
    final file = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  Future<int> newEntry([String title = '素材']) =>
      repo.saveEntry(EntryDraft(title: title, plainText: '正文'));

  Future<Asset> reload(int assetId) =>
      (db.select(db.assets)..where((a) => a.id.equals(assetId))).getSingle();

  // ─────────────────────────────────────────────────────────────────
  // 构造最小合法音频。WAV 最好造：RIFF 头 + fmt + data，时长 = data/byteRate。
  // 用它而不是 mp3 来测**时长**：mp3 的时长要从帧头/位率推算，手搓的帧很容易
  // 恰好算出 0，那会让用例的失败原因难以判断（是解析坏了还是素材本来就不像样）。
  // ─────────────────────────────────────────────────────────────────
  List<int> buildWav({required int dataBytes}) {
    const sampleRate = 8000;
    const channels = 1;
    const bitsPerSample = 8;
    const byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;

    final b = BytesBuilder();
    void ascii(String s) => b.add(s.codeUnits);
    void le32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    void le16(int v) => b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

    ascii('RIFF');
    le32(36 + dataBytes);
    ascii('WAVE');
    ascii('fmt ');
    le32(16);
    le16(1); // PCM
    le16(channels);
    le32(sampleRate);
    le32(byteRate);
    le16(blockAlign);
    le16(bitsPerSample);
    ascii('data');
    le32(dataBytes);
    b.add(Uint8List(dataBytes)); // 静音
    return b.takeBytes();
  }

  /// 最小 MP3：ID3v2.3 标签（含一张正封面）+ 一个合法 MPEG-1 Layer III 帧头。
  ///
  /// 为什么值得手搓：**封面这条路只有它能验**。用 WAV 测不了封面
  /// （RIFF 容器里带图要靠额外规范），而"封面对了没有"正是 P1-9 的一半。
  List<int> buildMp3WithCover(List<int> pngBytes) {
    final b = BytesBuilder();

    // ── APIC 帧：encoding(1) + mime + 0x00 + pictureType(1=coverFront) + desc + 0x00 + data
    final apicBody = BytesBuilder()
      ..addByte(0) // ISO-8859-1
      ..add('image/png'.codeUnits)
      ..addByte(0)
      ..addByte(3) // PictureType.coverFront
      ..addByte(0) // 空描述
      ..add(pngBytes);

    final frames = BytesBuilder();
    // APIC 帧头：ID + size(4, 普通大端) + flags(2)
    frames.add('APIC'.codeUnits);
    frames.add(Uint8List(4)..buffer.asByteData().setUint32(0, apicBody.length, Endian.big));
    frames.add(Uint8List(2));
    frames.add(apicBody.takeBytes());

    final frameBytes = frames.takeBytes();

    // ID3v2 头：ID3 + 版本 + flags + **syncsafe** 长度
    b.add('ID3'.codeUnits);
    b.addByte(3);
    b.addByte(0);
    b.addByte(0);
    final n = frameBytes.length;
    b.add(Uint8List.fromList([
      (n >> 21) & 0x7F,
      (n >> 14) & 0x7F,
      (n >> 7) & 0x7F,
      n & 0x7F,
    ]));
    b.add(frameBytes);

    // 一个 MPEG-1 Layer III 帧：0xFF 0xFB = MPEG1 / Layer3 / 无 CRC
    // 0x90 = 128kbps / 44100Hz；帧长 = 144*128000/44100 ≈ 417 字节
    final frame = Uint8List(417);
    frame[0] = 0xFF;
    frame[1] = 0xFB;
    frame[2] = 0x90;
    frame[3] = 0x00;
    b.add(frame);
    return b.takeBytes();
  }

  // ─────────────────────────────────────────────────────────────────
  // ① 时长
  // ─────────────────────────────────────────────────────────────────
  group('P1-9 音频时长', () {
    test('挂接 WAV：时长写进 durationMs（字段 W4 建表就为它留好了）', () async {
      final entryId = await newEntry();
      // 8000 Hz / 8bit / 单声道 → 每秒 8000 字节；给 2 秒
      final assetId = await repo.attachFile(
        entryId,
        writeTemp('录音.wav', buildWav(dataBytes: 16000)),
      );
      final asset = await reload(assetId);

      expect(asset.kind, AssetKind.audio.name);
      expect(asset.durationMs, isNotNull, reason: '时长必须落库');
      expect(asset.durationMs!, greaterThan(1800));
      expect(asset.durationMs!, lessThan(2200));
      // 音频没有"缩略图来源"以外的问题，但 WAV 无封面 → thumbPath 合法地为 null
      expect(asset.thumbPath, isNull);
    });

    test('读不出元信息也不影响挂接（不支持的容器 / 残缺文件）', () async {
      // .aac 在类型表里是 audio，但不在该解析库支持的容器列表里
      final entryId = await newEntry();
      final assetId =
          await repo.attachFile(entryId, writeTemp('残缺.aac', [0x01, 0x02, 0x03]));
      final asset = await reload(assetId);

      // 契约：任何文件都能记进来 —— 元信息只是加分项，读不出不能失败
      expect(asset.kind, AssetKind.audio.name);
      expect(asset.durationMs, isNull);
      expect(asset.originalName, '残缺.aac');
      expect((await MediaStorage().resolve(asset.relPath)).existsSync(), isTrue,
          reason: '文件本身必须好好存下来了');
    });

    test('时长格式化：分秒与时分秒两档', () {
      expect(formatDuration(null), isNull);
      expect(formatDuration(0), isNull, reason: '0 视为未知，不显示 0:00');
      expect(formatDuration(-5), isNull);
      expect(formatDuration(1000), '0:01');
      expect(formatDuration(225000), '3:45');
      expect(formatDuration(3600000), '1:00:00');
      expect(formatDuration(3727000), '1:02:07');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // ② 封面
  // ─────────────────────────────────────────────────────────────────
  group('P1-9 音频封面', () {
    test('带内嵌封面的 MP3：封面走缩略图管线生成 thumb', () async {
      // 封面用一张 300×300 的合法 PNG（管线要能解码它）
      final cover = img.encodePng(img.Image(width: 300, height: 300));
      final entryId = await newEntry();
      final assetId = await repo.attachFile(
        entryId,
        writeTemp('有封面.mp3', buildMp3WithCover(cover)),
      );
      final asset = await reload(assetId);

      expect(asset.thumbPath, isNotNull, reason: '内嵌封面应当被提取并转成缩略图');
      // 缩略图确实落盘了
      final thumb = await MediaStorage().resolve(asset.thumbPath!);
      expect(thumb.existsSync(), isTrue);
      // 而且被压到了 thumb 规格（长边 400）——直接存原封面会破坏这个契约
      final decoded = img.decodeImage(thumb.readAsBytesSync());
      expect(decoded, isNotNull);
      expect(decoded!.width <= 400 && decoded.height <= 400, isTrue);
    });

    test('封面不得覆盖音频文件自身的字节数与宽高（writeSourceMeta 的意义）', () async {
      final cover = img.encodePng(img.Image(width: 300, height: 300));
      final mp3Bytes = buildMp3WithCover(cover);
      final entryId = await newEntry();
      final assetId = await repo.attachFile(
        entryId,
        writeTemp('有封面.mp3', mp3Bytes),
      );
      final asset = await reload(assetId);

      // sizeBytes 必须是**音频文件**的大小：写成封面的字节数会让详情页
      // 显示一个凭空小掉两个数量级的"文件大小"
      expect(asset.sizeBytes, mp3Bytes.length,
          reason: '文件大小说的是那个音频文件，不是那张封面');
      // 音频没有有意义的宽高；把封面的 300×300 写进去同样是错的语义
      expect(asset.width, isNull);
      expect(asset.height, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // ③ P1-10 按附件类型筛选
  // ─────────────────────────────────────────────────────────────────
  group('P1-10 附件类型筛选', () {
    String writePdf(String name) =>
        writeTemp(name, const [0x25, 0x50, 0x44, 0x46]);
    String writePng(String name) =>
        writeTemp(name, img.encodePng(img.Image(width: 8, height: 8)));

    test('语义是「含该类附件」：同时带图与 PDF 的记录也应当命中', () async {
      final pdfOnly = await newEntry('只有 PDF');
      await repo.attachFile(pdfOnly, writePdf('a.pdf'));
      final imgOnly = await newEntry('只有图片');
      await repo.attachFile(imgOnly, writePng('b.png'));
      final both = await newEntry('两者都有');
      await repo.attachFile(both, writePdf('c.pdf'));
      await repo.attachFile(both, writePng('d.png'));
      final none = await newEntry('没有附件');

      final ids = await repo.selectIdsByFilter(
        filter: const TimelineFilter(attachmentKind: AssetKind.pdf),
      );
      expect(ids.toSet(), {pdfOnly, both},
          reason: '用户找的是"哪条记录里有 PDF"，同时带图的也该出现');

      final imgIds = await repo.selectIdsByFilter(
        filter: const TimelineFilter(attachmentKind: AssetKind.image),
      );
      expect(imgIds.toSet(), {imgOnly, both});

      // 不筛选时四条都在
      final all = await repo.selectIdsByFilter();
      expect(all.toSet(), {pdfOnly, imgOnly, both, none});
    });

    test('已软删的附件不算命中（否则筛选结果与卡片显示不一致）', () async {
      final removed = await newEntry('PDF 已移除');
      final assetId = await repo.attachFile(removed, writePdf('gone.pdf'));
      await db.assetsDao.softDelete(assetId);
      final kept = await newEntry('PDF 还在');
      await repo.attachFile(kept, writePdf('stay.pdf'));

      final ids = await repo.selectIdsByFilter(
        filter: const TimelineFilter(attachmentKind: AssetKind.pdf),
      );
      expect(ids.toSet(), {kept});
    });

    test('筛选必须下推 SQL：不能先 LIMIT 再筛', () async {
      // 三条记录，按日期倒序取前 2 条时**看不到**带 PDF 的那条。
      // 若在客户端过滤，结果会是空 —— 这正是 W7 定下"下推 where"那条红线的由来。
      final withPdf = await newEntry('最早的、带 PDF');
      await repo.attachFile(withPdf, writePdf('old.pdf'));
      await newEntry('中间一条');
      await newEntry('最新一条');

      final rows = await repo
          .watchTimeline(
            limit: 2,
            filter: const TimelineFilter(attachmentKind: AssetKind.pdf),
          )
          .first;
      expect(rows.map((e) => e.id), [withPdf]);
    });

    test('时间轴流与筛选条一致：结果里每条都真的带该类附件', () async {
      final withPdf = await newEntry('带 PDF');
      await repo.attachFile(withPdf, writePdf('x.pdf'));
      await newEntry('无附件');

      final rows = await repo
          .watchTimeline(
            filter: const TimelineFilter(attachmentKind: AssetKind.pdf),
          )
          .first;
      expect(rows, hasLength(1));
      expect(rows.single.id, withPdf);
      expect(rows.single.firstAttachmentKind, AssetKind.pdf);
    });

    test('TimelineFilter：等式 / 条件计数 / 清除附件类型', () {
      const plain = TimelineFilter();
      expect(plain.isEmpty, isTrue);
      expect(plain.activeCount, 0);

      const withPdf = TimelineFilter(attachmentKind: AssetKind.pdf);
      expect(withPdf.isEmpty, isFalse);
      expect(withPdf.activeCount, 1);
      expect(withPdf == const TimelineFilter(attachmentKind: AssetKind.pdf), isTrue,
          reason: '等式必须带上新维度，否则"筛选变了要清空已选"会失灵');
      expect(withPdf == plain, isFalse);
      expect(withPdf.hashCode == plain.hashCode, isFalse);

      expect(withPdf.copyWith(clearAttachmentKind: true), plain);
      expect(
        withPdf.copyWith(pinnedOnly: true).activeCount,
        2,
        reason: '两个维度可叠加',
      );
    });

    testWidgets('筛选弹层的「附件类型」段把选择写进 provider', (tester) async {
      // 数据层已经验过语义，这里只验**接线**：chip 点下去真的写进了 filter。
      // 少了这条，"chip 手滑写成另一个字段"这类错误不会有任何测试变红。
      final container = ProviderContainer(
        overrides: [dbProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const TimelinePage())],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: PlainLeafApp(routerConfig: router),
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('筛选'));
      await _settle(tester);

      // 弹层是纵向的，先保证目标滚进可视区再点，避免被有限高度裁掉
      await tester.ensureVisible(find.text('附件类型'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.widgetWithText(FilterChip, 'PDF'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.ensureVisible(find.text('查看结果'));
      await tester.tap(find.text('查看结果'));
      await _settle(tester);

      expect(container.read(timelineFilterProvider).attachmentKind,
          AssetKind.pdf,
          reason: '「附件类型」chip 必须落到 filter 的同一维度上');
      expect(container.read(timelineFilterProvider).activeCount, 1);

      await _drainWidgets(tester);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

/// 有界落定：时间轴是 StreamProvider，不用 pumpAndSettle（加载态会让它等到超时）
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 卸载树并消化 drift 流退订排队的 0 延时 Timer，避免 pending-timer 误报
Future<void> _drainWidgets(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
