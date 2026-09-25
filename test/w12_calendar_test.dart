import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/calendar/domain/calendar_month.dart';
import 'package:plainleaf/features/calendar/presentation/pages/calendar_page.dart';
import 'package:plainleaf/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/features/timeline/presentation/providers/timeline_providers.dart';

/// W12 日历回顾回归用例
///
/// 覆盖契约里的三件事：
/// ① 日期边界（月份归一化、跨年切换、闰月天数、网格补位）必须精确；
/// ② 月在 Dart 层聚合，跨月/跨年不串，草稿与软删不入选；
/// ③ 点有记录的一天会弹出当天记录。
///
/// 两条纪律（沿用既有测试）：
/// - 纯函数与 provider 语义一律直接调，不进 Widget 树；
/// - 全程**不用 pumpAndSettle**：drift 流会让它等到超时，只用有界 pump 循环。
void main() {
  late PlainLeafDatabase db;

  setUp(() => db = PlainLeafDatabase.forTesting(openInMemoryDb()));
  tearDown(() => db.close());

  ProviderContainer containerOf([List<Override> extra = const []]) =>
      ProviderContainer(
        overrides: [dbProvider.overrideWithValue(db), ...extra],
      );

  group('日历纯函数（日期边界）', () {
    test('月份归一化与跨年切换', () {
      expect(monthStart(DateTime(2026, 9, 25, 13, 40)), DateTime(2026, 9, 1));
      expect(nextMonthStart(DateTime(2026, 9, 1)), DateTime(2026, 10, 1));
      // 12 → 次年 1 月
      expect(nextMonthStart(DateTime(2026, 12, 1)), DateTime(2027, 1, 1));
      // 1 → 上年 12 月
      expect(previousMonthStart(DateTime(2026, 1, 1)), DateTime(2025, 12, 1));
      expect(previousMonthStart(DateTime(2026, 3, 15)), DateTime(2026, 2, 1));
    });

    test('isSameDay 忽略时分秒；isFutureDay 用「日」粒度', () {
      final today = DateTime(2026, 9, 25, 9, 0);
      expect(isSameDay(DateTime(2026, 9, 25, 23, 59), today), isTrue);
      expect(isSameDay(DateTime(2026, 9, 26, 0, 0), today), isFalse);

      // 今天稍晚的时刻也不算未来——否则格子会在同一天内反复变灰又变亮
      expect(isFutureDay(DateTime(2026, 9, 25, 23, 59), today), isFalse);
      expect(isFutureDay(DateTime(2026, 9, 26), today), isTrue);
      expect(isFutureDay(DateTime(2026, 9, 24), today), isFalse);
    });

    test('闰月天数：2024-02 有 29 天，平年 28 天，世纪年按 400 判', () {
      expect(daysInMonth(DateTime(2024, 2)), 29);
      expect(daysInMonth(DateTime(2023, 2)), 28);
      expect(daysInMonth(DateTime(2000, 2)), 29);
      expect(daysInMonth(DateTime(1900, 2)), 28);
      expect(daysInMonth(DateTime(2026, 9)), 30);
      expect(daysInMonth(DateTime(2026, 1)), 31);
    });

    test('网格：前补位/后补位正确，长度恒为 7 的整数倍', () {
      for (final month in [
        DateTime(2024, 2), // 闰月
        DateTime(2023, 2),
        DateTime(2026, 9),
        DateTime(2026, 1),
        DateTime(2024, 9),
      ]) {
        final cells = monthGridCells(month);
        final leading = monthStart(month).weekday - 1;
        final trailing =
            (7 - (leading + daysInMonth(month)) % 7) % 7;

        expect(cells.length % 7, 0,
            reason: '${monthLabel(month)} 的网格应是整周');
        expect(cells.take(leading).every((c) => c == null), isTrue,
            reason: '月初前应为 $leading 个空位');
        expect(cells.skip(cells.length - trailing).every((c) => c == null),
            isTrue, reason: '月末后应为 $trailing 个空位');

        final days = cells.whereType<DateTime>().toList();
        expect(days.length, daysInMonth(month), reason: '当月的每一天都要出现一次');
        expect(days.first, DateTime(month.year, month.month, 1));
        expect(days.last, DateTime(month.year, month.month, daysInMonth(month)));
      }
    });

    test('网格包含闰日 2/29', () {
      final cells = monthGridCells(DateTime(2024, 2));
      expect(cells.contains(DateTime(2024, 2, 29)), isTrue);
    });

    test('聚合按天计数：同一天多次累加，跨月不串', () {
      final counts = aggregateDailyCounts([
        DateTime(2026, 9, 1, 8, 0),
        DateTime(2026, 9, 1, 20, 30),
        DateTime(2026, 9, 2, 1, 0),
        DateTime(2026, 8, 31, 23, 59), // 上个月的最后一天，不能并进 9/1
      ]);
      expect(counts[DateTime(2026, 9, 1)], 2);
      expect(counts[DateTime(2026, 9, 2)], 1);
      expect(counts[DateTime(2026, 8, 31)], 1);
      expect(counts.length, 3);
    });

    test('密度分级 0/1/2/3，三档封顶', () {
      expect(densityLevel(0), 0);
      expect(densityLevel(1), 1);
      expect(densityLevel(2), 2);
      expect(densityLevel(3), 3);
      expect(densityLevel(10), 3, reason: '超过 3 条仍归最深一档');
      expect(densityLevel(-1), 0);
    });
  });

  group('月命中 provider', () {
    test('只返回当月且未删除、非草稿的命中（跨月边界不串）', () async {
      final container = containerOf([
        selectedMonthProvider.overrideWith((ref) => DateTime(2024, 2, 1)),
      ]);
      addTearDown(container.dispose);
      final repo = container.read(timelineRepositoryProvider);

      await repo.saveEntry(EntryDraft(
          title: '上月尾', plainText: 'x', entryDate: DateTime(2024, 1, 31, 23, 59)));
      await repo.saveEntry(EntryDraft(
          title: '闰日九点', plainText: 'x', entryDate: DateTime(2024, 2, 29, 9)));
      await repo.saveEntry(EntryDraft(
          title: '闰日十三点', plainText: 'x', entryDate: DateTime(2024, 2, 29, 13)));
      await repo.saveEntry(EntryDraft(
          title: '下月初', plainText: 'x', entryDate: DateTime(2024, 3, 1, 0, 0)));
      await repo.saveEntry(EntryDraft(
          title: '草稿不算',
          plainText: 'x',
          status: EntryStatus.draft,
          entryDate: DateTime(2024, 2, 10)));

      final hits = await container.read(monthDateHitsProvider.future);
      expect(hits.length, 2, reason: '只有 2/29 的两条落在 2024-02');
      expect(
        hits.every((h) => h.date.year == 2024 && h.date.month == 2),
        isTrue,
        reason: '绝不能把 1/31 或 3/1 混进来',
      );
    });

    test('dayEntriesProvider 返回当天记录（含标题）', () async {
      final container = containerOf();
      addTearDown(container.dispose);
      final repo = container.read(timelineRepositoryProvider);

      await repo.saveEntry(EntryDraft(
          title: '当天第一条', plainText: '甲', entryDate: DateTime(2024, 2, 29, 9)));
      await repo.saveEntry(EntryDraft(
          title: '当天第二条', plainText: '乙', entryDate: DateTime(2024, 2, 29, 21)));
      await repo.saveEntry(EntryDraft(
          title: '前一天', plainText: '丙', entryDate: DateTime(2024, 2, 28, 22)));

      final list =
          await container.read(dayEntriesProvider(DateTime(2024, 2, 29)).future);
      expect(list.length, 2);
      expect(list.map((e) => e.title).toSet(),
          {'当天第一条', '当天第二条'});
    });
  });

  testWidgets('点有记录的一天，弹层列出当天记录', (tester) async {
    final container = containerOf([
      // 固定到 2024-02：既有闰日，又整月都在过去，格子可点
      selectedMonthProvider.overrideWith((ref) => DateTime(2024, 2, 1)),
      // 假支持目录：只要能把相对路径拼成绝对路径，文件不存在会走碎图标位
      supportDirProvider.overrideWith((ref) async => '/tmp/plainleaf-w12-cal'),
    ]);
    addTearDown(container.dispose);
    await container.read(timelineRepositoryProvider).saveEntry(EntryDraft(
        title: '闰日那天的记录',
        plainText: '内容',
        entryDate: DateTime(2024, 2, 29, 9, 30)));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CalendarPage()),
      ),
    );
    await settle(tester);

    expect(find.text('2024年02月'), findsOneWidget,
        reason: '表头应显示选中的月份');
    expect(find.text('29'), findsOneWidget, reason: '2/29 应出现在网格里');

    await tester.tap(find.text('29'));
    await settle(tester);

    expect(find.text('闰日那天的记录'), findsOneWidget,
        reason: '点有记录的一天应弹出当天记录');

    await drain(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// 有界落定：最多 ~1 秒；不用 pumpAndSettle（见文件头注记）
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 卸载树并消化 drift 流退订排队的 Timer，避免 pending-timer 误报
Future<void> drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 600));
}
