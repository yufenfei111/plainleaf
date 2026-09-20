import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/search/presentation/search_page.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// 递归收集 TextSpan 的文本段（Text.rich 会多包一层，需下钻）
void collectSpanTexts(InlineSpan span, List<String> out) {
  if (span is! TextSpan) return;
  if (span.text != null) out.add(span.text!);
  for (final child in span.children ?? const <InlineSpan>[]) {
    collectSpanTexts(child, out);
  }
}

/// 搜索页验收（§5.3 Widget 测试清单：搜索高亮；issue #12）
/// 覆盖两点：① 高亮切分函数的边界；② 真机上「搜得到 + 关键词被切成多段」。
void main() {
  late PlainLeafDatabase db;

  setUp(() async {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
    final repo = LocalTimelineRepository(db.entriesDao);
    await repo.saveEntry(
      const EntryDraft(title: '学习记录', plainText: '今天复习线性代数'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('高亮切分（纯函数）', () {
    const base = TextStyle();
    const hit = TextStyle();

    test('命中中间词：切成 前/中/后 三段', () {
      final spans = buildHighlightSpans('abcXdef', ['x'], base: base, hit: hit);
      expect(spans.length, 3);
    });

    test('无查询词或无命中：返回单段', () {
      expect(buildHighlightSpans('abc', [], base: base, hit: hit).length, 1);
      expect(buildHighlightSpans('abc', ['z'], base: base, hit: hit).length, 1);
    });

    test('重叠命中合并，不重复切段', () {
      final spans = buildHighlightSpans('aaa', ['aa'], base: base, hit: hit);
      expect(spans.length, 2);
    });
  });

  testWidgets('搜索命中：结果渲染为多段高亮文本', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '学习');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    // 命中一条：结果卡渲染出来
    expect(find.byType(ListTile), findsWidgets);

    // 关键词被切成独立高亮段。注意 Text.rich 会再包一层 TextSpan，
    // 所以要递归下钻，不能只看顶层 children。
    final texts = <String>[];
    for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
      collectSpanTexts(w.text, texts);
    }
    expect(texts, contains('学习'), reason: '命中词应被切成独立高亮段');
    expect(texts, contains('记录'), reason: '未命中部分应作为普通段保留');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
