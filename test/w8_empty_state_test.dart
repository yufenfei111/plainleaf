import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/search/presentation/search_page.dart';
import 'package:plainleaf/main.dart';
import 'package:plainleaf/shared/widgets/empty_state.dart';

/// 测试隔离用路由：把待测页面挂到根路径（避开全局路由表与未实现的子路由）。
GoRouter _testRouter(Widget child) => GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (context, state) => child)],
    );

void main() {
  late PlainLeafDatabase db;

  setUp(() {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
  });

  tearDown(() async {
    await db.close();
  });

  group('EmptyState 组件', () {
    testWidgets('① 只传必填参数时不渲染任何按钮', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.search_outlined,
              title: '输入关键词开始搜索',
            ),
          ),
        ),
      );
      expect(find.text('输入关键词开始搜索'), findsOneWidget);
      // 主/次级按钮都不应出现
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      // 图标渲染到位
      expect(find.byIcon(Icons.search_outlined), findsOneWidget);
    });

    testWidgets('② 传 actionLabel+onAction 后点击能触发回调', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.book_outlined,
              title: '还没有笔记本',
              actionLabel: '新建笔记本',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('新建笔记本'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(tapped, isTrue);
    });

    testWidgets('③ 只传 secondary 时渲染次级按钮且点击触发', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.search_off,
              title: '没有匹配的记录',
              secondaryActionLabel: '清除筛选',
              onSecondaryAction: () => tapped = true,
            ),
          ),
        ),
      );
      // 没有主按钮，只有次级 TextButton
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(TextButton), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      expect(tapped, isTrue);
    });

    testWidgets('④ 搜索页空数据（未输入）显示对应空态文案', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: PlainLeafApp(routerConfig: _testRouter(const SearchPage())),
        ),
      );
      await tester.pumpAndSettle();
      // 内存库无数据且未输入关键词 → 应显示「未输入」引导文案
      expect(find.text('输入关键词开始搜索'), findsOneWidget);
      expect(find.text('没有匹配的记录'), findsNothing);
    });

    testWidgets('⑤ 搜索页「未输入」与「无结果」两种文案确实不同', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: PlainLeafApp(routerConfig: _testRouter(const SearchPage())),
        ),
      );
      await tester.pumpAndSettle();

      // 初始：未输入状态
      expect(find.text('输入关键词开始搜索'), findsOneWidget);

      // 输入一个库里不存在的词并触发搜索
      await tester.enterText(find.byType(TextField), '不存在的关键词xyz');
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();

      // 切换为「无结果」状态，原「未输入」文案应消失
      expect(find.text('没有匹配的记录'), findsOneWidget);
      expect(find.text('输入关键词开始搜索'), findsNothing);
    });
  });
}
