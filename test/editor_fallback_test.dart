import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/editor/presentation/editor_page.dart';
import 'package:plainleaf/main.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// 回归：contentDelta 为空但 plainText 有内容的记录（种子数据、W3 前落库的条目）
/// 打开编辑器时正文必须显示出来，且保存后不能被清空。
///
/// 背景：编辑器以 Delta 为准。若解析空 Delta 直接给空文档，用户点「完成」
/// 触发 flush 保存时，会用空文档覆盖正文——属于数据丢失级缺陷。
void main() {
  late PlainLeafDatabase db;

  setUp(() async {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('Delta 为空时回退 plainText，且保存不丢正文', (tester) async {
    final repo = LocalTimelineRepository(db.entriesDao);
    // EntryDraft 默认 contentDelta 为空串 —— 正是缺陷复现场景
    final id = await repo.saveEntry(
      const EntryDraft(title: '只有纯文本的老记录', plainText: '历史正文甲乙丙'),
    );

    // 用 PlainLeafApp 承载：flutter_quill 工具栏 tooltip 需要 FlutterQuillLocalizations，
    // 裸 MaterialApp 会因缺 delegate 抛异常（35 个异常的来源）
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => EditorPage(entryId: id)),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    // 编辑器首帧是 loading，等 _bootstrap 完成
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 标题回显（说明确实加载到了这条记录）
    expect(find.text('只有纯文本的老记录'), findsOneWidget);

    // 改一下标题触发防抖保存（正文未改动，应保持原文）
    await tester.enterText(find.byType(TextField).first, '只有纯文本的老记录2');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 200));

    final row = await db.entriesDao.findById(id);
    expect(row, isNotNull);
    expect(row!.plainText, contains('历史正文甲乙丙'),
        reason: '保存后正文不应被空 Delta 覆盖');
    expect(row.title, '只有纯文本的老记录2');
    expect(row.contentDelta, isNotEmpty, reason: '回填后应写回有效 Delta');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
