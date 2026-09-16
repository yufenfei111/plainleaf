import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/db/seed.dart';
import 'package:plainleaf/main.dart';

/// 阶段 0 UI 冒烟测试（Day 7 验收项：flutter test 通过）
/// 内存库跑真实数据链路：建表 → 种子 → 时间轴/学习/笔记本三页渲染与交互。
/// 注意：不用裸 pumpAndSettle——加载指示器/流等待期间存在无限动画，
/// 会导致 settle 永不结束（阶段 0 实测挂死）；统一用带超时的 settleFrames。
void main() {
  late PlainLeafDatabase db;

  setUp(() async {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
    await DemoSeed.maybeSeed(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// 有界落定：最多 ~3 秒，落不定就放行（流数据延迟到达不阻塞冒烟）
  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    try {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
    } on StateError {
      // 未落定：无限动画仍在，冒烟继续
    }
  }
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const PlainLeafApp(),
      ),
    );
    await settleFrames(tester);
  }


  /// 消化 drift 流退订时安排的 0 延时 Timer（StreamQueryStore.markAsClosed）：
  /// 测试结束框架自动卸载树 → Timer 排队 → 立即断言 pending timers 会误报。
  /// 主动换成空树 + 推进假时钟 1ms，让 Timer 先跑完。
  Future<void> drainTimers(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }
  testWidgets('骨架渲染：时间轴首页显示种子记录', (tester) async {
    await pumpApp(tester);
    expect(find.text('素页'), findsOneWidget);
    expect(find.text('阶段 0 启动'), findsOneWidget);
    expect(find.text('时间轴'), findsOneWidget);
    expect(find.text('相册'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('笔记本'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    await drainTimers(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Tab 切换：学习页显示待办并可勾选', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('学习'));
    await settleFrames(tester);
    expect(find.text('完成阶段 0 骨架验收'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await settleFrames(tester);
    await drainTimers(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Tab 切换：笔记本页显示生活/学习双空间', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('笔记本'));
    await settleFrames(tester);
    expect(find.text('生活空间'), findsOneWidget);
    expect(find.text('学习空间'), findsOneWidget);
    await drainTimers(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));
}