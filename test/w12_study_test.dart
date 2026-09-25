import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/study/domain/daily_completion.dart';
import 'package:plainleaf/features/study/domain/entities/study_todo.dart';
import 'package:plainleaf/features/study/presentation/providers/study_providers.dart';
import 'package:plainleaf/features/study/presentation/study_page.dart';

/// W12 学习 Tab「每日完成数 + 已完成也能删」回归用例
///
/// 覆盖三块：
/// ① [dailyCompletion] 纯函数：日期归一 / 空列表 / 全完成 / 全未完成 /
///    未完成跨天跟随 / completedAt 缺失回退 —— 统计口径只此一处，锁住它就锁住了
///    顶部文案与进度条的共同真相；
/// ② 今日概况 Provider 与 UI：数字要跟着待办流走，盘子为空时整条让位；
/// ③ 「已完成待办左滑软删 → 撤销」链路（W12 相对 W11 的唯一差别：W11 的已完成
///    段落是只读的）。这条链路两端都在数据流上，必须证明软删与撤销都真的落库。
///
/// 纪律（沿用 W11 写法）：provider 层语义用 ProviderContainer 直驱、不进 Widget 树；
/// Widget 用例**不用 pumpAndSettle**——页面是 StreamProvider，settle 只会等到超时，
/// 一律用有界的 pump 循环。
void main() {
  /// 造一条待办：默认创建于 2026-09-25 上午，避免用例里到处重复填充字段
  StudyTodo makeTodo({
    required int id,
    bool done = false,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return StudyTodo(
      id: id,
      content: '任务 $id',
      done: done,
      createdAt: createdAt ?? DateTime(2026, 9, 25, 9),
      completedAt: completedAt,
    );
  }

  /// 当天（只取年月日）
  final day = DateTime(2026, 9, 25);

  group('dailyCompletion 纯函数', () {
    test('空列表：盘子为空，比率给 0 而不是 NaN', () {
      final stats = dailyCompletion(const <StudyTodo>[], day);
      expect(stats.total, 0);
      expect(stats.done, 0);
      expect(stats.ratio, 0.0, reason: '0/0 必须收敛成 0，否则进度条整条消失');
      expect(stats.percent, 0);
    });

    test('日期归一到年月日：同一天的 00:01 与 23:59 都算今天', () {
      final justAfterMidnight = DateTime(2026, 9, 25, 0, 0, 1);
      final justBeforeMidnight = DateTime(2026, 9, 25, 23, 59, 59);
      final list = [
        makeTodo(id: 1, done: true, completedAt: justAfterMidnight),
        makeTodo(id: 2, done: true, completedAt: justBeforeMidnight),
      ];
      // 传进来的「今天」带时分秒也必须被归一，不能要求调用方先 truncate
      final stats = dailyCompletion(list, DateTime(2026, 9, 25, 15, 30));
      expect(stats.total, 2);
      expect(stats.done, 2);
      expect(stats.ratio, 1.0);
      expect(stats.percent, 100);
    });

    test('隔天完成的既不计数也不占今天盘子', () {
      final stats = dailyCompletion([
        makeTodo(id: 1, done: true, completedAt: DateTime(2026, 9, 24, 23, 59)),
        makeTodo(id: 2, done: true, completedAt: DateTime(2026, 9, 26, 0, 1)),
      ], day);
      expect(stats.total, 0);
      expect(stats.done, 0);
      expect(stats.ratio, 0.0);
    });

    test('未完成的一律算进今天：昨天遗留的今天仍压着，不该从盘子里消失', () {
      final stats = dailyCompletion([
        makeTodo(id: 1, createdAt: DateTime(2026, 9, 20, 8)),
      ], day);
      expect(stats.total, 1,
          reason: '按创建日归属会让第二天打开时「共 0」而列表里还躺着几条');
      expect(stats.done, 0);
      expect(stats.percent, 0);
    });

    test('全未完成：done 为 0、total 为条数、比率 0', () {
      final stats = dailyCompletion([
        makeTodo(id: 1),
        makeTodo(id: 2),
        makeTodo(id: 3),
      ], day);
      expect(stats.total, 3);
      expect(stats.done, 0);
      expect(stats.ratio, 0.0);
      expect(stats.percent, 0);
    });

    test('全完成：done == total、比率 1.0、百分比正好 100', () {
      final stats = dailyCompletion([
        makeTodo(id: 1, done: true, completedAt: DateTime(2026, 9, 25, 9)),
        makeTodo(id: 2, done: true, completedAt: DateTime(2026, 9, 25, 12)),
        makeTodo(id: 3, done: true, completedAt: DateTime(2026, 9, 25, 18)),
      ], day);
      expect(stats.total, 3);
      expect(stats.done, 3);
      expect(stats.ratio, 1.0);
      expect(stats.percent, 100);
    });

    test('百分比向下取整：2/3 显示 66 而不是看着像做完的四舍五入值', () {
      final stats = dailyCompletion([
        makeTodo(id: 1, done: true, completedAt: DateTime(2026, 9, 25, 9)),
        makeTodo(id: 2, done: true, completedAt: DateTime(2026, 9, 25, 10)),
        makeTodo(id: 3),
      ], day);
      expect(stats.total, 3);
      expect(stats.done, 2);
      expect(stats.percent, 66);
    });

    test('completedAt 缺失的已完成条目退回创建日：不凭空消失，也不重复计数', () {
      final stats = dailyCompletion([
        makeTodo(id: 1, done: true, createdAt: DateTime(2026, 9, 25, 7)),
        makeTodo(id: 2, done: true, createdAt: DateTime(2026, 9, 24, 7)),
      ], day);
      expect(stats.total, 1, reason: '只有创建于今天的这一条归属今天');
      expect(stats.done, 1);
    });
  });

  group('今日概况（Provider 与 UI）', () {
    late PlainLeafDatabase db;

    setUp(() => db = PlainLeafDatabase.forTesting(openInMemoryDb()));
    tearDown(() => db.close());

    ProviderContainer containerOf() =>
        ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);

    /// 有界落定：最多 ~1 秒；不用 pumpAndSettle（见文件头注记）
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// 卸载树并消化 drift 流退订排队的 0 延时 Timer，避免 pending-timer 误报
    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    }

    /// 等到条件成立为止：drift 流要过事件循环才下发，纯 test 里没有 pump，
    /// 只能让出事件循环轮询；超时即判定失败，不会静默放过。
    /// 预算给到 ~2 秒：首次查询还包含内存库建表，冷启动头一次会慢一些。
    Future<void> waitUntil(bool Function() ready) async {
      for (var i = 0; i < 200; i++) {
        if (ready()) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('等待今日概况更新超时');
    }

    test('todayStatsProvider 跟着待办流走：勾完成 done +1，取消后回落', () async {
      final container = containerOf();
      addTearDown(container.dispose);

      final repo = container.read(todoRepositoryProvider);
      final actions = container.read(todoActionsProvider);

      // 不读一次的话 todayStatsProvider 根本不会去听待办流
      container.listen(todayStatsProvider, (previous, next) {},
          fireImmediately: true);

      final id = (await actions.addTodo('背 20 个单词'))!;
      await waitUntil(() => container.read(todayStatsProvider).total == 1);
      expect(container.read(todayStatsProvider).done, 0);

      await repo.setDone(id, value: true);
      await waitUntil(() => container.read(todayStatsProvider).done == 1);
      expect(container.read(todayStatsProvider).total, 1);

      await repo.setDone(id, value: false);
      await waitUntil(() => container.read(todayStatsProvider).done == 0);
    });

    testWidgets('UI：顶部显示「今天完成 N / 共 M」，盘子为空时整条让位', (tester) async {
      final container = containerOf();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: StudyPage()),
        ),
      );
      await settle(tester);

      expect(find.textContaining('今天完成'), findsNothing,
          reason: '还没有任务时不该挂一条 0/0 的噪音');

      await tester.enterText(find.byType(TextField), '整理错题本');
      await settle(tester);
      await tester.tap(find.byIcon(Icons.add));
      await settle(tester);

      expect(find.text('今天完成 0 / 共 1'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget,
          reason: '只要有一件没完成，今天就有盘子可画');

      await tester.tap(find.byType(Checkbox));
      await settle(tester);
      expect(find.text('今天完成 1 / 共 1'), findsOneWidget);

      await drain(tester);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('已完成待办软删 → 撤销', () {
    late PlainLeafDatabase db;

    setUp(() => db = PlainLeafDatabase.forTesting(openInMemoryDb()));
    tearDown(() => db.close());

    ProviderContainer containerOf() =>
        ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    }

    test('已完成条目走的是软删：行留在库里、completion 状态原样保留、可撤销回来', () async {
      final container = containerOf();
      addTearDown(container.dispose);

      final repo = container.read(todoRepositoryProvider);
      final actions = container.read(todoActionsProvider);

      final id = (await actions.addTodo('复盘错题'))!;
      await repo.setDone(id, value: true);

      final doneTodo =
          (await repo.watchTodos().first).firstWhere((t) => t.id == id);
      expect(doneTodo.done, isTrue);
      expect(doneTodo.completedAt, isNotNull,
          reason: '勾完成必须写 completedAt，这是每日完成数的唯一数据源');

      // W12 的关键补充：已完成条目同样能删，而且删除红线不变——只软删
      await actions.deleteTodo(id);
      expect((await repo.watchTodos().first).any((t) => t.id == id), isFalse,
          reason: '软删后不应再出现在列表流里');

      final row = await (db.select(db.todos)..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.deleted, isTrue, reason: '删除一律软删：行必须还在库里');
      expect(row.done, isTrue, reason: '软删只翻 deleted，不该顺手清掉完成态');

      await actions.restoreTodo(id);
      final restored =
          (await repo.watchTodos().first).firstWhere((t) => t.id == id);
      expect(restored.done, isTrue, reason: '撤销删除要原样复原，包括完成态');
    });

    testWidgets('UI：已完成待办左滑软删，SnackBar 的「撤销」把它带回来', (tester) async {
      final container = containerOf();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: StudyPage()),
        ),
      );
      await settle(tester);

      // 录一条并勾成已完成：唯一一条待办会落进「已完成」段落
      await tester.enterText(find.byType(TextField), '整理实验报告');
      await settle(tester);
      await tester.tap(find.byIcon(Icons.add));
      await settle(tester);
      await tester.tap(find.byType(Checkbox));
      await settle(tester);

      expect(find.text('已完成'), findsOneWidget);
      expect(find.byType(Dismissible), findsOneWidget,
          reason: '已完成段落里的条目也必须能左滑，不能退回 W11 的只读');

      await tester.drag(find.byType(Dismissible), const Offset(-600, 0));
      await settle(tester);

      expect(find.text('整理实验报告'), findsNothing, reason: '软删后应离开列表');
      expect(find.text('已删除「整理实验报告」'), findsOneWidget,
          reason: '删除后必须给出撤销入口，否则软删的意义就丢了');

      await tester.tap(find.text('撤销'));
      await settle(tester);

      expect(find.text('整理实验报告'), findsOneWidget,
          reason: '点「撤销」后这一条要回到列表');
      final row = await (db.select(db.todos)
            ..where((t) => t.content.equals('整理实验报告')))
          .getSingle();
      expect(row.deleted, isFalse, reason: '撤销要真的落库，不能只是 UI 假象');
      expect(row.done, isTrue, reason: '复原后仍是已完成状态');

      await drain(tester);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
