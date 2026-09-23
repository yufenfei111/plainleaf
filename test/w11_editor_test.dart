import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/editor/presentation/editor_page.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/main.dart';

/// W11 编辑器打磨
///
/// 现有测试（autosave / editor_fallback / w10_fixes / smoke）已经重度依赖编辑器，
/// 这里不再叠 UI 复杂度：可测的三条规则抽成纯函数直接单测，
/// 只留一条极简 Widget 用例守住「字数真的显示在页面上」。
/// 不用 pumpAndSettle：页面里有流与指示器的加载态，settle 会拖到超时而不是快速失败。
void main() {
  test('① 字数统计：空白不计，中英文按字符计', () {
    expect(countBodyChars(''), 0);
    expect(countBodyChars('  \n\t '), 0, reason: '纯空白不该算字数');
    expect(countBodyChars('abc'), 3);
    expect(countBodyChars('中文abc'), 5, reason: '中英文同权，各计 1');
    expect(countBodyChars('a b\nc'), 3, reason: '空格与换行不计入');
  });

  test('② 全屏大图解码宽度：屏幕宽×DPR，并夹在合理区间', () {
    expect(fullscreenCacheWidth(400, 3), 1200);
    expect(fullscreenCacheWidth(0, 3), 1, reason: '测量值为 0 时不能传 0 给 cacheWidth');
    expect(fullscreenCacheWidth(4000, 4), 4096, reason: '超高 DPR 也要有上限');
  });

  test('③ 退出拦截：只在「有内容且未落库」时拦一次', () {
    expect(shouldConfirmExit(dirty: true, empty: false, bypass: false), isTrue);

    expect(
      shouldConfirmExit(dirty: true, empty: true, bypass: false),
      isFalse,
      reason: '空记录退出即回收，不该用对话框拦一下',
    );
    expect(
      shouldConfirmExit(dirty: false, empty: false, bypass: false),
      isFalse,
      reason: '已落库再拦就是打扰',
    );
    expect(
      shouldConfirmExit(dirty: true, empty: false, bypass: true),
      isFalse,
      reason: '发布 / 已确认的程序性退出必须直接放行',
    );
  });

  test('④ 全屏大图来源：优先 medium，缺失回退原图', () {
    expect(viewerRelPath('media/a.jpg', 'media/a_m.jpg'), 'media/a_m.jpg');
    expect(viewerRelPath('media/a.jpg', null), 'media/a.jpg');
  });

  testWidgets('⑤ 编辑器底部显示正文字数', (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = LocalTimelineRepository(db.entriesDao);
    final id = await repo.saveEntry(
      const EntryDraft(title: '字数验收', plainText: '历史正文甲乙丙'),
    );

    // 用 PlainLeafApp 承载：quill 工具栏的 tooltip 需要 FlutterQuillLocalizations，
    // 裸 MaterialApp 会因缺 delegate 抛异常
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => EditorPage(entryId: id)),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    // 首帧是 loading，等 _bootstrap 加载完
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('7 字'), findsOneWidget, reason: '正文字数应显示且不含空白');

    // 收尾：销毁树并推进时间，清掉 drift watch / 防抖的残留 Timer，
    // 否则测试结束时的「Timer is still pending」会直接判失败
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
