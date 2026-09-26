import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/media/attachment_picker.dart';
import 'package:plainleaf/core/media/file_opener.dart';
import 'package:plainleaf/core/storage/media_storage.dart';
import 'package:plainleaf/features/editor/presentation/editor_page.dart';
import 'package:plainleaf/features/editor/presentation/providers/editor_providers.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/main.dart';

/// W17 P0-4 / P0-5：附件条从「只认图片」改为「按类型分派」。
///
/// 守住三件事：
///   ① 非图片附件能挂进来，并在附件条上显示类型徽标（而不是破图占位）
///   ② 点开非图片 → 把**正确的绝对路径**交给系统应用（用 RecordingFileOpener 断言）
///   ③ 用户取消选择时什么都不发生（不落库、不提示）
///
/// 为什么必须用测试替身：`file_picker` / `open_filex` 都走平台通道，
/// 在测试宿主里调用必抛 MissingPluginException —— 这正是这两个能力被抽成接口的原因。
void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('plainleaf_w17_ui');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  group('ScriptedAttachmentPicker（替身自身的行为）', () {
    test('用户取消：返回 null 且不抛异常', () async {
      final picker = ScriptedAttachmentPicker([null]);
      expect(await picker.pickFile(), isNull);
      expect(picker.callCount, 1);
    });

    test('脚本用尽后返回 null（等价于用户又点了取消）', () async {
      final picker = ScriptedAttachmentPicker([]);
      expect(await picker.pickFile(), isNull);
    });
  });

  group('RecordingFileOpener', () {
    test('记录被提交给系统打开的全部路径', () async {
      final opener = RecordingFileOpener();
      await opener.open('/tmp/a.pdf');
      await opener.open('/tmp/b.docx');
      expect(opener.opened, ['/tmp/a.pdf', '/tmp/b.docx']);
    });
  });

  testWidgets('挂接 PDF：附件条显示类型徽标，点开交给系统应用', (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = LocalTimelineRepository(
      db.entriesDao,
      assetsDao: db.assetsDao,
      mediaStorage: MediaStorage(),
    );
    final entryId = await repo.saveEntry(
      const EntryDraft(title: '附件验收', plainText: '正文'),
    );

    // 造一个真的本机 PDF（内容只要文件头，探测按文件头走）
    final tmp = Directory.systemTemp.createTempSync('plainleaf_w17_pdf');
    final pdf = File('${tmp.path}/作业第三章.pdf')
      ..writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37]);

    final opener = RecordingFileOpener();
    final picker = ScriptedAttachmentPicker([
      PickedAttachment(path: pdf.path, name: '作业第三章.pdf'),
    ]);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => EditorPage(entryId: entryId)),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          attachmentPickerProvider.overrideWithValue(picker),
          fileOpenerProvider.overrideWithValue(opener),
        ],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 点「选择文件」→ 挂接
    await tester.tap(find.byTooltip('选择文件（任意类型）'));
    // 挂接要走**真实文件复制 + 数据库写入**：`pump` 只推进虚拟时钟，等不到真实 I/O，
    // 直接断言会看到"交互发生了但没落库"。必须用 runAsync 让真实异步跑完。
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 分层断言：先确认「交互发生了」「落库成功了」，最后才看 UI。
    // 这样一旦失败能立刻区分是点击没生效、挂接失败、还是渲染没刷新。
    expect(picker.callCount, 1, reason: '应真的调用了选择器');

    // 诊断：页面把挂接异常 catch 掉后只弹 SnackBar，不弹的话错误就被吞了。
    // 先把提示文本取出来，失败时能直接看到真实原因，不必反复猜。
    final failureTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.contains('失败'))
        .toList();
    expect(failureTexts, isEmpty, reason: '挂接不应失败，实际提示：$failureTexts');

    expect(await db.assetsDao.allByEntry(entryId), hasLength(1),
        reason: '选中的文件应已落库');

    // ① 附件条显示扩展名徽标（非图片不该出现破图占位）
    expect(find.text('PDF'), findsOneWidget,
        reason: '非图片附件应以类型徽标呈现');
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing,
        reason: 'PDF 不该被当作图片去渲染');

    // ② 点开 → 交给系统应用，且路径正确（拼上了支持目录）
    await tester.tap(find.text('PDF'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(opener.opened, hasLength(1), reason: '非图片应交给系统应用打开');
    expect(opener.opened.first, endsWith('.pdf'));
    expect(opener.opened.first, contains('media'));

    // 收尾：销毁树会触发防抖 flush（一次真实写库），
    // 先让 I/O 跑完再交给 tearDown 关库 —— 顺序反了会出现
    // 「Can't re-open a database after closing it」的次生错误，掩盖真正的失败原因。
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump(const Duration(milliseconds: 600));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('用户取消选择文件：不挂接、不提示', (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = LocalTimelineRepository(
      db.entriesDao,
      assetsDao: db.assetsDao,
      mediaStorage: MediaStorage(),
    );
    final entryId = await repo.saveEntry(
      const EntryDraft(title: '取消验收', plainText: '正文'),
    );

    final picker = ScriptedAttachmentPicker([null]); // 第一次就取消
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => EditorPage(entryId: entryId)),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          attachmentPickerProvider.overrideWithValue(picker),
        ],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.byTooltip('选择文件（任意类型）'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(picker.callCount, 1, reason: '应该真的调了一次选择器');
    expect(await db.assetsDao.allByEntry(entryId), isEmpty,
        reason: '取消是正常操作，不该落任何库');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump(const Duration(milliseconds: 600));
  }, timeout: const Timeout(Duration(seconds: 60)));
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
