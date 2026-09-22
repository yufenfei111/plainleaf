import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/editor/presentation/trash_page.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_filter.dart';
import 'package:plainleaf/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:plainleaf/features/timeline/presentation/timeline_page.dart';
import 'package:plainleaf/main.dart';

/// W8 验收：时间轴/回收站空态改造 + 详情页入口。
///
/// 关键：外层必须用 PlainLeafApp（挂着 FlutterQuillLocalizations.delegate），
/// 并通过其 routerConfig 注入自定义 GoRouter（每个用例独立路由实例，避免跨用例污染）。
void main() {
  late PlainLeafDatabase db;

  setUp(() => db = PlainLeafDatabase.forTesting(openInMemoryDb()));
  tearDown(() => db.close());

  /// 有界落定：最多 ~2 秒，落不定就放行——
  /// 时间轴用的是 StreamProvider，数据延迟到达不应阻塞断言。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// 卸载树并消化 drift 流退订排队的 0 延时 Timer，避免 pending-timer 误报
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('① 空库无筛选：显示「还没有记录」且不显示「清除筛选」',
      (tester) async {
    final container = ProviderContainer(
      overrides: [dbProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const TimelinePage()),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    await settle(tester);

    // 库里一条记录都没有 → 欢迎式引导文案
    expect(find.text('还没有记录'), findsOneWidget);
    // 无筛选时不应出现「清除筛选」入口
    expect(find.text('清除筛选'), findsNothing);

    await drain(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('② 筛选后无结果：显示「清除筛选」，点击后重置为默认',
      (tester) async {
    final container = ProviderContainer(
      overrides: [dbProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    // 预置一个必然筛空的筛选（库里没有任何置顶记录）
    container.read(timelineFilterProvider.notifier).state =
        const TimelineFilter(pinnedOnly: true);

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const TimelinePage()),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    await settle(tester);

    // 有筛选但无结果 → 明确归因到筛选
    expect(find.text('没有符合条件的记录'), findsOneWidget);
    final clearButton = find.text('清除筛选');
    expect(clearButton, findsOneWidget);

    await tester.tap(clearButton);
    await settle(tester);

    // 点击后筛选条件被重置回默认（provider state 直接断言）
    expect(container.read(timelineFilterProvider), const TimelineFilter());

    await drain(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('③ 有数据时点击卡片跳转到 /detail?id=N', (tester) async {
    final repo = LocalTimelineRepository(db.entriesDao);
    final id = await repo.saveEntry(
      const EntryDraft(title: '跳转测试', plainText: '正文'),
    );

    // 自定义路由：/detail 用占位页记录 query 参数，断言跳转目标
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const TimelinePage()),
        GoRoute(
          path: '/detail',
          builder: (ctx, state) {
            final q = state.uri.queryParameters['id'] ?? '';
            return Scaffold(body: Center(child: Text('DETAIL_PAGE:$q')));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    await settle(tester);

    // 时间轴渲染出这条记录
    expect(find.text('跳转测试'), findsOneWidget);
    await tester.ensureVisible(find.text('跳转测试'));
    await tester.tap(find.text('跳转测试'));
    await settle(tester);

    // 卡片点击应推到 /detail?id=N（用占位页渲染内容断言）
    expect(find.text('DETAIL_PAGE:$id'), findsOneWidget);

    await drain(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('④ 回收站为空：显示新空态文案而非旧「回收站是空的」',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const TrashPage()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    await settle(tester);

    // 旧的那句纯文本不应再出现
    expect(find.text('回收站是空的'), findsNothing);
    // 新的空态文案 + 30 天保留说明
    expect(find.text('回收站里还没有记录'), findsOneWidget);
    expect(find.textContaining('保留 30 天'), findsOneWidget);

    await drain(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
