import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/app/router.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/db/settings_store.dart';
import 'package:plainleaf/features/onboarding/data/onboarding_content.dart';
import 'package:plainleaf/features/onboarding/presentation/manual_art.dart';
import 'package:plainleaf/features/onboarding/presentation/manual_page.dart';
import 'package:plainleaf/features/onboarding/presentation/onboarding_page.dart';
import 'package:plainleaf/features/timeline/presentation/timeline_page.dart';
import 'package:plainleaf/main.dart';

/// W22 新手引导与内置操作手册
///
/// 守住四条：
///   ① 首次启动首屏是引导，已看过则直接进时间轴（两态都要验，否则"永远显示引导"也能过）
///   ② 跳过会**写入标记**——否则下次启动又弹，等于没做
///   ③ 手册把全部章节都渲染出来（漏章是这类"数据驱动页面"最常见的退化）
///   ④ 有配图的条目真的渲染了示意图
///
/// 纪律沿用既有测试：不用 `pumpAndSettle`（启动过场与图片解码会让它等到超时），
/// 只做有界 pump；涉及真实写库的地方用 `runAsync`（否则断言时数据还没落库）。
void main() {
  late PlainLeafDatabase db;

  setUp(() => db = PlainLeafDatabase.forTesting(openInMemoryDb()));
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester, {required bool showOnboarding}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: PlainLeafApp(
          routerConfig: buildAppRouter(showOnboarding: showOnboarding),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 收尾：销毁树 + 让真实 I/O 跑完，再交给 tearDown 关库
  Future<void> settleDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('① 首次启动：首屏是新手引导', (tester) async {
    await pumpApp(tester, showOnboarding: true);

    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.text('欢迎使用素页'), findsOneWidget);
    // 第一页就能看到跳过入口
    expect(find.byKey(const Key('onboarding-skip')), findsOneWidget);

    await settleDown(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('② 已看过引导：首屏直接是时间轴', (tester) async {
    await pumpApp(tester, showOnboarding: false);

    expect(find.byType(OnboardingPage), findsNothing,
        reason: '看过之后不该再弹引导');
    expect(find.byType(TimelinePage), findsOneWidget);

    await settleDown(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('③ 引导能翻到最后一页，按钮文案变成「开始使用」', (tester) async {
    await pumpApp(tester, showOnboarding: true);

    for (var i = 0; i < kOnboardingSlides.length - 1; i++) {
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('开始使用'), findsOneWidget);
    // 最后一页应该能看到末页的说明（讲应用锁）
    expect(find.text('该上锁的地方上好锁'), findsOneWidget);

    await settleDown(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('④ 点跳过：写入「已看过」标记并进入主界面', (tester) async {
    await pumpApp(tester, showOnboarding: true);

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    // 跳过会写库（真实 I/O）+ 跳路由，pump 等不到写库完成
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final seen = await SettingsStore(db).readString(SettingKeys.onboardingSeen);
    expect(seen, '1',
        reason: '不写标记的话下次启动又弹一遍 —— 那这个引导就是纯打扰');
    expect(find.byType(OnboardingPage), findsNothing);

    await settleDown(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('⑤ 操作手册：全部章节都渲染出来', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ManualPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 章节多、列表长：手册页是 ListView，视口外的章节不会构建 ——
    // 这里放大视口，让全部章节一次性进入构建范围（沿用 W11 的做法）
    tester.view.physicalSize = const Size(900, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pump(const Duration(milliseconds: 200));

    for (final section in kManualSections) {
      expect(find.text(section.title), findsOneWidget,
          reason: '章节「${section.title}」没渲染出来');
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('⑥ 展开带配图的章节，示意图真的渲染了', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ManualPage()),
      ),
    );
    tester.view.physicalSize = const Size(900, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pump(const Duration(milliseconds: 200));

    // 「相册与浏览」章里有一条带手势示意图
    final gallerySection =
        kManualSections.firstWhere((s) => s.title.contains('相册'));
    expect(gallerySection.entries.any((e) => e.art == ManualArt.viewerGestures),
        isTrue, reason: '相册章应当配手势示意图');

    await tester.tap(find.text(gallerySection.title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ManualArtView), findsWidgets,
        reason: '配了图的条目必须真的把图渲染出来');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  }, timeout: const Timeout(Duration(seconds: 60)));

  group('内容约束（纯数据，防止"空壳章节"混进来）', () {
    test('引导页数量与字段完整', () {
      expect(kOnboardingSlides.length, 4);
      for (final s in kOnboardingSlides) {
        expect(s.title.trim(), isNotEmpty);
        expect(s.body.trim(), isNotEmpty);
        expect(s.highlights, isNotEmpty, reason: '${s.title} 一条要点都没有');
      }
    });

    test('每章都有摘要与非空条目，条目正文不为空', () {
      expect(kManualSections.length, greaterThanOrEqualTo(8));
      for (final s in kManualSections) {
        expect(s.summary.trim(), isNotEmpty, reason: '${s.title} 缺摘要');
        expect(s.entries, isNotEmpty, reason: '${s.title} 是空章');
        for (final e in s.entries) {
          expect(e.title.trim(), isNotEmpty);
          expect(e.body.trim(), isNotEmpty,
              reason: '${s.title} → ${e.title} 正文为空');
        }
      }
    });

    test('配图克制：不是每条都配图', () {
      final total = kManualSections.fold<int>(
          0, (sum, s) => sum + s.entries.length);
      final withArt = kManualSections
          .expand((s) => s.entries)
          .where((e) => e.art != null)
          .length;
      expect(withArt, greaterThan(0), reason: '手册不能只有文字');
      expect(withArt, lessThan(total),
          reason: '每条都配图，图就变成噪音了 —— 只在说不清的地方配');
    });
  });
}
