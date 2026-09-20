import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/app/router.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/db/seed.dart';
import 'package:plainleaf/main.dart';

/// 编辑器自动保存专项测试（§5.3 Widget 测试清单：编辑器自动保存 500ms 防抖）
/// 与 smoke_test 的「新建→发布」冒烟互补：本例不点「完成」，
/// 只靠防抖窗口落库，并在窗口内断言尚未写入，验证防抖确实生效。
void main() {
  late PlainLeafDatabase db;

  setUp(() async {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
    await DemoSeed.maybeSeed(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: PlainLeafApp(routerConfig: buildAppRouter()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<bool> titleSaved(String title) async {
    final rows = await db.select(db.entries).get();
    return rows.any((e) => e.title == title);
  }

  testWidgets('500ms 防抖：窗口内不落库，越过窗口自动保存', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('记一笔'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).first, '防抖验收标题');

    // 防抖窗口内（<500ms）：尚未落库
    await tester.pump(const Duration(milliseconds: 200));
    expect(await titleSaved('防抖验收标题'), isFalse,
        reason: '500ms 防抖窗口内不应写入');

    // 越过窗口：自动保存触发（异步写库再给一帧）
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(await titleSaved('防抖验收标题'), isTrue,
        reason: '越过防抖窗口应自动落库');

    // 消化 drift 流退订安排的 0 延时 Timer
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
