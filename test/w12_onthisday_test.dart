import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/features/timeline/presentation/providers/on_this_day_provider.dart';
import 'package:plainleaf/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:plainleaf/features/timeline/presentation/widgets/on_this_day_card.dart';
import 'package:plainleaf/shared/widgets/skeleton.dart';

/// W12「那年今日」回归用例
///
/// 覆盖契约里的三件事：
/// ① 只有「往年同月同日」才入选，今年今天与往年异日都必须排除，且新 → 旧；
/// ② 最多 3 条；
/// ③ 卡片：有数据渲染对应条数；无数据塌成 **0 尺寸**（绝不是一块留白）。
///
/// 纪律（沿用既有 W11/W12 测试）：provider 语义用 ProviderContainer 直测；
/// Widget 测试**不用 pumpAndSettle**，一律有界 pump 循环（drift 流会让 settle 超时）。
void main() {
  late PlainLeafDatabase db;

  setUp(() => db = PlainLeafDatabase.forTesting(openInMemoryDb()));
  tearDown(() => db.close());

  /// 钉住「今天」，用例才不会随运行日历漂移（见 onThisDayTodayProvider 的注释）
  final pinnedToday = DateTime(2026, 9, 25);

  ProviderContainer containerOf() => ProviderContainer(
        overrides: [
          dbProvider.overrideWithValue(db),
          onThisDayTodayProvider.overrideWithValue(pinnedToday),
        ],
      );

  group('onThisDayProvider', () {
    test('只取往年同月同日，且按新 → 旧排序', () async {
      final container = containerOf();
      addTearDown(container.dispose);
      final repo = container.read(timelineRepositoryProvider);

      await repo.saveEntry(EntryDraft(
          title: '两年前', plainText: 'a', entryDate: DateTime(2024, 9, 25, 10)));
      await repo.saveEntry(EntryDraft(
          title: '一年前', plainText: 'b', entryDate: DateTime(2025, 9, 25, 10)));
      // 今年今天：年份相同，必须排除
      await repo.saveEntry(EntryDraft(
          title: '今年今天', plainText: 'c', entryDate: DateTime(2026, 9, 25, 9)));
      // 往年但不是同一天：必须排除
      await repo.saveEntry(EntryDraft(
          title: '往年异日', plainText: 'd', entryDate: DateTime(2025, 9, 26, 10)));

      final items = await container.read(onThisDayProvider.future);
      expect(items.map((i) => i.title).toList(), ['一年前', '两年前'],
          reason: '新 → 旧，且只留往年同日');
      expect(items.first.yearsAgo, 1);
      expect(items.last.yearsAgo, 2);
    });

    test('最多 3 条', () async {
      final container = containerOf();
      addTearDown(container.dispose);
      final repo = container.read(timelineRepositoryProvider);

      for (var years = 1; years <= 4; years++) {
        await repo.saveEntry(EntryDraft(
          title: '$years 年前',
          plainText: 'x',
          entryDate: DateTime(2026 - years, 9, 25, 10),
        ));
      }

      final items = await container.read(onThisDayProvider.future);
      expect(items.length, 3, reason: '卡片最多展示 3 条');
    });
  });

  group('OnThisDayCard', () {
    testWidgets('有数据：渲染对应条数、标题与「N 年前」标签', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supportDirProvider.overrideWith((ref) async => '/tmp/plainleaf-w12'),
            onThisDayProvider.overrideWith(
              (ref) => Stream<List<OnThisDayItem>>.value(const [
                OnThisDayItem(
                  id: 1,
                  title: '三年前写的',
                  yearsAgo: 3,
                  thumbRelPath: 'thumb/2023/a.jpg',
                ),
                OnThisDayItem(id: 2, title: '一年前写的', yearsAgo: 1),
              ]),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: OnThisDayCard())),
        ),
      );
      await settle(tester);

      expect(find.text('那年今日'), findsOneWidget);
      expect(find.text('三年前写的'), findsOneWidget);
      expect(find.text('一年前写的'), findsOneWidget);
      expect(find.text('3 年前'), findsOneWidget);
      expect(find.text('1 年前'), findsOneWidget);
      // 有 thumbRelPath 的那条应带一张缩略图
      expect(find.byType(Image), findsOneWidget);

      await drain(tester);
    });

    testWidgets('无数据：塌成 0 尺寸，不留白', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onThisDayProvider.overrideWith(
              (ref) => Stream<List<OnThisDayItem>>.value(const []),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  OnThisDayCard(),
                  Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('那年今日'), findsNothing);
      expect(find.byType(Card), findsNothing);
      // 关键断言：整张卡片高度为 0，顶部不会凭空多出一块空白
      expect(tester.getSize(find.byType(OnThisDayCard)).height, 0);

      await drain(tester);
    });

    testWidgets('加载中：显示静态骨架占位，不是空白', (tester) async {
      // 永不吐值的流：让 provider 停在 AsyncLoading
      final controller = StreamController<List<OnThisDayItem>>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onThisDayProvider.overrideWith((ref) => controller.stream),
          ],
          child: const MaterialApp(home: Scaffold(body: OnThisDayCard())),
        ),
      );
      await settle(tester);

      expect(find.byType(SkeletonBox), findsWidgets,
          reason: '加载态应给同形骨架，而不是留白');

      await drain(tester);
    });

    testWidgets('出错：给出重试入口，不是空白', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onThisDayProvider.overrideWith(
              (ref) => Stream<List<OnThisDayItem>>.error(Exception('boom')),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: OnThisDayCard())),
        ),
      );
      await settle(tester);

      expect(find.text('那年今日加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await drain(tester);
    });
  });
}

/// 有界落定：最多 ~1 秒；不用 pumpAndSettle（见文件头注记）
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 卸载树并消化 drift / 图片解码残留的 Timer，避免 pending-timer 误报
Future<void> drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 600));
}
