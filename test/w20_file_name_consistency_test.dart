import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/media/attachment_handoff.dart';
import 'package:plainleaf/core/media/file_opener.dart';
import 'package:plainleaf/core/media/image_saver.dart';
import 'package:plainleaf/core/storage/media_storage.dart';
import 'package:plainleaf/features/detail/presentation/entry_detail_page.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// W20：交出去的文件名必须与列表里显示的名字一致
///
/// ## 报的问题
/// 「详情页附件区列表标题显示的是文件名，点开后实际文件名却是一串英文/乱码」。
///
/// ## 根因
/// 盘上落的是 `media/yyyy/mm/<uuid>.pdf`（uuid 去重、避免路径注入 —— 这是**对的设计**），
/// 而列表标题显示的是 `assets.original_name`（「作业第三章.pdf」）。
/// 此前把**盘上路径**直接交给系统应用，于是系统标题栏与"另存为"的默认名都是 uuid。
///
/// ## 所以这里守的是
///   ① 展示名 → 可落盘文件名的清理规则（含路径穿越、非法字符、超长中文名）
///   ② 交出时的文件名 == 展示名，且内容与源文件逐字节一致
///   ③ 盘上文件名本就等于展示名时**不复制**（历史数据不必平白多占一份空间）
///   ④ 不同附件同名时互不顶掉；同一附件反复打开不重复复制
///   ⑤ "打开"与"保存"两条链路共用同一套命名规则（否则同一个附件会有两个名字）
final Directory _root =
    Directory.systemTemp.createTempSync('plainleaf_w20_names');

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePaths(_root.path);
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

  String writeTemp(String name, String content) {
    final tmp = Directory.systemTemp.createTempSync('plainleaf_w20_src');
    final file = File('${tmp.path}/$name')..writeAsStringSync(content);
    return file.path;
  }

  /// 内容是真的 PDF 文件头 + 一段可辨认的正文（用于逐字节比对）
  String writePdf([String name = '作业第三章.pdf']) =>
      writeTemp(name, '%PDF-1.7 正文内容甲');

  // ─────────────────────────────────────────────────────────────────
  // ① 清理规则
  // ─────────────────────────────────────────────────────────────────
  group('safeDisplayFileName：展示名 → 可落盘文件名', () {
    test('中文名原样保留（这是本功能存在的理由）', () {
      expect(safeDisplayFileName('作业第三章.pdf'), '作业第三章.pdf');
      expect(safeDisplayFileName('毕业论文终稿 v2.docx'), '毕业论文终稿 v2.docx');
    });

    test('带路径分隔符时只取文件名，不让人跳出目标目录', () {
      // 展示名理论上来自文件名，但"文件名可控"就必须按可控处理：
      // 若这里原样返回，p.join(slot, name) 会把文件写到目录之外。
      expect(safeDisplayFileName('../../etc/passwd'), 'passwd');
      expect(safeDisplayFileName(r'..\..\Windows\system.ini'), 'system.ini');
      expect(safeDisplayFileName('a/b.pdf'), 'b.pdf');
      // 只剩一个分隔符时也不能漏出一个名叫 `/` 的文件
      expect(safeDisplayFileName('/'), isNot('/'));
    });

    test('替换路径非法字符与控制字符（Windows 上写不进去的那些）', () {
      expect(safeDisplayFileName('a<b>c:d"e|f?g*h.pdf'), 'a_b_c_d_e_f_g_h.pdf');
      expect(safeDisplayFileName('坏${String.fromCharCode(0x01)}名.pdf'),
          '坏_名.pdf');
    });

    test('去掉结尾的点与空格（Windows 会静默丢弃，导致名字对不上）', () {
      expect(safeDisplayFileName('报告.pdf.'), '报告.pdf');
      expect(safeDisplayFileName('报告.pdf '), '报告.pdf');
      expect(safeDisplayFileName('报告.pdf..  '), '报告.pdf');
    });

    test('得不到可用名字时返回 null（调用方回退原路径）', () {
      expect(safeDisplayFileName(null), isNull);
      expect(safeDisplayFileName(''), isNull);
      expect(safeDisplayFileName('.'), isNull);
      expect(safeDisplayFileName('..'), isNull);
      expect(safeDisplayFileName('   '), isNull);
    });

    test('超长中文名按 UTF-8 字节截断：不按字符数截，且保留扩展名', () {
      // 中文一个字占 3 字节：按"字符数"截断会在中文长标题上照样超限，
      // 届时得到的是"文件名过长"的写盘失败 —— 比截断更难排查。
      final long = '${'作' * 100}.pdf';
      final safe = safeDisplayFileName(long)!;
      expect(utf8.encode(safe).length, lessThanOrEqualTo(200));
      expect(safe.endsWith('.pdf'), isTrue, reason: '扩展名必须留下，否则系统认不出类型');
      expect(safe.startsWith('作'), isTrue);
    });

    test('截断不会切碎多字节字符（不会产生非法 UTF-16）', () {
      final safe = safeDisplayFileName('${'好' * 100}文.pdf')!;
      // 能重新编码回同样的字节 → 没有落在半个字符上
      expect(utf8.decode(utf8.encode(safe)), safe);
      expect(safe.contains('\uFFFD'), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // ② 交出前的准备
  // ─────────────────────────────────────────────────────────────────
  group('AttachmentHandoff.prepare', () {
    late Directory staging;
    late Directory srcDir;
    late AttachmentHandoff handoff;

    setUp(() {
      staging = Directory.systemTemp.createTempSync('plainleaf_w20_stage');
      // 源必须放在暂存目录**之外**：有一条用例要断言暂存目录没有任何条目
      srcDir = Directory.systemTemp.createTempSync('plainleaf_w20_srcs');
      handoff = AttachmentHandoff(stagingRoot: () async => staging);
    });

    tearDown(() {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
    });

    /// 造一个"库内形态"的源文件：uuid 名字 + 展示名
    File uuidFile(String uuid, String content) =>
        File(p.join(srcDir.path, '$uuid.pdf'))..writeAsStringSync(content);

    test('盘上是 uuid → 交出去的 basename 是展示名，内容逐字节一致', () async {
      final source = uuidFile('0f3a9c11', '%PDF-1.7 正文内容甲');
      final out = await handoff.prepare(
        sourceAbsPath: source.path,
        displayName: '作业第三章.pdf',
      );

      expect(p.basename(out), '作业第三章.pdf');
      expect(File(out).readAsStringSync(), source.readAsStringSync(),
          reason: '只是换了个名字，内容不能被动过');
      expect(out, isNot(source.path));
    });

    test('盘上文件名已等于展示名 → 不复制（历史数据没有原名，展示名回退成文件名）',
        () async {
      final source = uuidFile('deadbeef', '%PDF-1.7 x');
      final out = await handoff.prepare(
        sourceAbsPath: source.path,
        displayName: p.basename(source.path), // displayName 的回退形态
      );

      expect(out, source.path, reason: '名字本就一致，不该平白多占一份空间');
      // 暂存目录里不该出现这个附件
      final entries = staging.listSync().whereType<Directory>();
      expect(entries, isEmpty);
    });

    test('展示名不可用（null / `..`）→ 原样交回，不抛异常', () async {
      final source = uuidFile('aaaa1111', '%PDF-1.7 x');
      expect(
        await handoff.prepare(sourceAbsPath: source.path, displayName: null),
        source.path,
      );
      expect(
        await handoff.prepare(sourceAbsPath: source.path, displayName: '..'),
        source.path,
      );
    });

    test('源文件不在盘上 → 原样交回（让系统去报"文件不存在"更准确）', () async {
      final missing = p.join(staging.path, 'nope', 'cccc2222.pdf');
      final out = await handoff.prepare(
        sourceAbsPath: missing,
        displayName: '不见了.pdf',
      );
      expect(out, missing);
    });

    test('两个不同附件挂同名文件 → 互不顶掉，且各自都叫那个名字', () async {
      final a = uuidFile('11112222', 'A 的内容');
      final b = uuidFile('33334444', 'B 的内容');

      final outA = await handoff.prepare(
        sourceAbsPath: a.path,
        displayName: '作业.pdf',
      );
      final outB = await handoff.prepare(
        sourceAbsPath: b.path,
        displayName: '作业.pdf',
      );

      expect(outA, isNot(outB), reason: '同名不能互相覆盖');
      expect(p.basename(outA), '作业.pdf');
      expect(p.basename(outB), '作业.pdf');
      expect(File(outA).readAsStringSync(), 'A 的内容');
      expect(File(outB).readAsStringSync(), 'B 的内容');
      // 副本放在以库内文件名命名的**子目录**里（所以整条路径里能看到 uuid），
      // 但交出去的那个**文件名**不能被 uuid 污染 ——
      // 给"另存为"默认名加 uuid 前缀是最省事的做法，而那恰恰是本轮要修的毛病。
      expect(p.basename(outA), isNot(contains('11112222')));
      expect(p.basename(outB), isNot(contains('33334444')));
    });

    test('同一附件反复打开 → 复用已有副本，不重复复制', () async {
      final source = uuidFile('55556666', 'ABCDEFGH'); // 8 字节
      final first = await handoff.prepare(
        sourceAbsPath: source.path,
        displayName: '反复打开.pdf',
      );
      // 把副本内容改成等长的另一串：若第二次是"重新复制"，内容会被覆盖回去
      File(first).writeAsStringSync('XXXXXXXX');
      final second = await handoff.prepare(
        sourceAbsPath: source.path,
        displayName: '反复打开.pdf',
      );

      expect(second, first);
      expect(File(second).readAsStringSync(), 'XXXXXXXX',
          reason: '大小一致即复用，不该重写（反复点开几十 MB 的附件时这点很关键）');
    });

    test('副本目录名不含展示名 → 展示名里的特殊字符不会影响目录结构', () async {
      final source = uuidFile('77778888', 'x');
      final out = await handoff.prepare(
        sourceAbsPath: source.path,
        displayName: '带*星号?的名字.pdf',
      );
      expect(p.basename(out), '带_星号_的名字.pdf');
      expect(p.basename(p.dirname(out)), '77778888');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // ③ 详情页：这是用户报的那个场景
  // ─────────────────────────────────────────────────────────────────
  testWidgets('详情页：点开附件，交给系统的文件名 == 列表标题', (tester) async {
    final opener = RecordingFileOpener();
    final entryId = (await tester.runAsync(() async {
      final id = await repo.saveEntry(
        const EntryDraft(title: '附件文件名', plainText: '正文'),
      );
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

    // 列表标题（用户看到的那个名字）
    expect(find.text('作业第三章.pdf'), findsOneWidget);

    await tester.tap(find.text('作业第三章.pdf'));
    // 交出前要按展示名复制一份（真实文件 I/O）→ 必须 runAsync
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(opener.opened, hasLength(1));
    expect(p.basename(opener.opened.single), '作业第三章.pdf',
        reason: '系统应用里看到的名字必须与列表标题一致（这正是本次修复的 bug）');
    expect(File(opener.opened.single).existsSync(), isTrue,
        reason: '交出去的必须是真实存在的文件');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  // ─────────────────────────────────────────────────────────────────
  // ④ 保存：与"打开"同源
  // ─────────────────────────────────────────────────────────────────
  group('保存到磁盘：文件名与展示名一致', () {
    test('桌面实现按 asName 落盘，且仍不覆盖同名文件', () async {
      final source = writeTemp('0f3a9c11.pdf', '%PDF-1.7 内容');
      final first = await const DesktopImageSaver()
          .save(source, asName: '作业第三章.pdf');
      final second = await const DesktopImageSaver()
          .save(source, asName: '作业第三章.pdf');

      expect(p.basename(first.detail), '作业第三章.pdf');
      expect(p.basename(second.detail), '作业第三章-1.pdf');
      expect(File(first.detail).readAsStringSync(), '%PDF-1.7 内容');
    });

    test('展示名不带扩展名时补上源文件的扩展名（否则系统认不出类型）', () async {
      final source = writeTemp('bbb.png', 'PNGDATA');
      final result = await const DesktopImageSaver()
          .save(source, asName: '随手拍');
      expect(p.basename(result.detail), '随手拍.png');
    });

    test('没给展示名时退回源文件名（老调用点行为不变）', () async {
      final source = writeTemp('plain.png', 'PNGDATA');
      final result = await const DesktopImageSaver().save(source);
      expect(p.basename(result.detail), 'plain.png');
    });

    test('targetFileNameFor 与「打开」走同一套清理规则', () {
      // 两条链路各写一份清理逻辑的结局，必然是同一个附件两个名字
      expect(targetFileNameFor('/x/0f3a.pdf', '../../坏?名.pdf'), '坏_名.pdf');
      expect(targetFileNameFor('/x/uuid.bin', null), 'uuid.bin');
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

  @override
  Future<String?> getDownloadsPath() async => root;

  /// 交出前的副本落在临时目录 —— 这条必须实现，否则 getTemporaryDirectory
  /// 会抛 MissingPlatformDirectoryException，表现为"点开没反应"
  @override
  Future<String?> getTemporaryPath() async => root;
}
