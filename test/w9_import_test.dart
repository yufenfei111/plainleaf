import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/importer/data/markdown_import_service.dart';
import 'package:plainleaf/features/importer/domain/markdown_importer.dart';
import 'package:plainleaf/features/importer/presentation/markdown_import_page.dart';
import 'package:plainleaf/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:plainleaf/main.dart';

void main() {
  group('Markdown 解析器', () {
    // ① 单条：标题/日期/类型/心情正确，标记被剥掉
    test('单条解析：头信息识别 + Markdown 标记剥除', () {
      const md = '''
# 我的标题
日期：2026-09-22
类型：diary
心情: 4

这是 **加粗** 与 *斜体* 还有 `代码`。
- 列表项一
- 列表项二
链接：[百度](https://baidu.com)
''';
      final list = parseMarkdown(md);
      expect(list, hasLength(1));
      final e = list.single;
      expect(e.title, '我的标题');
      expect(e.entryDate, DateTime(2026, 9, 22));
      expect(e.type.name, 'diary');
      expect(e.mood, 4);
      // 标记应被剥掉，文字应保留
      expect(e.plainText, isNot(contains('**')));
      expect(e.plainText, isNot(contains('*斜体*')));
      expect(e.plainText, isNot(contains('`')));
      expect(e.plainText, contains('加粗'));
      expect(e.plainText, contains('斜体'));
      expect(e.plainText, contains('代码'));
      expect(e.plainText, contains('列表项一'));
      expect(e.plainText, contains('百度'));
      expect(e.plainText, isNot(contains('[')));
    });

    // ② 多条：--- 分隔切成多条
    test('多条：--- 分隔切分为多条记录', () {
      const md = '''
# 标题一
正文一
---
# 标题二
正文二
''';
      final list = parseMarkdown(md);
      expect(list, hasLength(2));
      expect(list[0].title, '标题一');
      expect(list[1].title, '标题二');
    });

    // ③ 无标题回退 + 空输入返回空列表不抛异常
    test('无标题回退到正文首行，空/空白输入返回空列表', () {
      // 空输入
      expect(parseMarkdown(''), isEmpty);
      expect(parseMarkdown('   \n  \n'), isEmpty);
      // 无标题：取正文首行作标题
      final list = parseMarkdown('今天去散步\n天气不错');
      expect(list, hasLength(1));
      expect(list.single.title, '今天去散步');
      expect(list.single.plainText, '天气不错');
    });
  });

  // ④ 落库：内存库 + 真实 LocalTimelineRepository 导入一条，随后能查到
  test('落库：导入一条后可在时间轴查到该记录', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    final container = ProviderContainer(
      overrides: [dbProvider.overrideWithValue(db)],
    );
    addTearDown(db.close);

    final repo = container.read(timelineRepositoryProvider);
    final service = MarkdownImportService(repo);
    final count = await service.importMarkdown('# 落库测试\n这是正文内容');
    expect(count, 1);

    final entries = await repo.watchTimeline().first;
    expect(entries.any((e) => e.title == '落库测试'), isTrue);
  });

  // ⑤ 页面：渲染出输入框与导入按钮
  testWidgets('页面渲染输入框与「开始导入」按钮', (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const MarkdownImportPage(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始导入'), findsOneWidget);
    addTearDown(db.close);
  });
}
