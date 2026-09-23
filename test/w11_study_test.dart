import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/study/presentation/providers/study_providers.dart';
import 'package:plainleaf/features/study/presentation/study_page.dart';

/// W11 学习 Tab「补录入」回归用例
///
/// 三条 provider/仓库层用例覆盖契约里的三件事：
/// ① 录入一行后能在流里读到；② 空输入/纯空格不落库（不该产生幽灵行）；
/// ③ 左滑删除是**软删**且可撤销（§4.3 删除红线）。
/// 再加一条 UI 用例证明「在输入框里敲一行 → 列表多一条」这条主路径是通的。
///
/// 纪律（沿用既有 W11 测试的写法）：provider 层语义直接用 ProviderContainer 驱动，
/// 不进 Widget 树；UI 用例**不用 pumpAndSettle**——页面是 StreamProvider，
/// 流等待会让 settle 只等到超时，一律用有界的 pump 循环。
void main() {
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

  test('① 添加待办：写库后流里能读到，且默认为未完成', () async {
    final container = containerOf();
    addTearDown(container.dispose);

    final id = await container.read(todoActionsProvider).addTodo('整理错题本');
    expect(id, isNotNull, reason: '非空内容应正常落库');

    final list =
        await container.read(todoRepositoryProvider).watchTodos().first;
    final hit = list.firstWhere((t) => t.id == id, orElse: () => throw StateError('流里没有这条待办'));
    expect(hit.content, '整理错题本');
    expect(hit.done, isFalse, reason: '新录入的一律是未完成，不该默认勾上');
  });

  test('② 空输入与纯空格不落库', () async {
    final container = containerOf();
    addTearDown(container.dispose);

    final actions = container.read(todoActionsProvider);
    expect(await actions.addTodo(''), isNull, reason: '空串应被忽略');
    expect(await actions.addTodo('   '), isNull, reason: '纯空格应被忽略');

    final list =
        await container.read(todoRepositoryProvider).watchTodos().first;
    expect(list, isEmpty, reason: '被忽略的录入不该在库里留下幽灵行');
  });

  test('③ 删除是软删：行仍在库里，可撤销回来', () async {
    final container = containerOf();
    addTearDown(container.dispose);

    final actions = container.read(todoActionsProvider);
    final repo = container.read(todoRepositoryProvider);

    final id = await actions.addTodo('背 20 个单词');
    await actions.deleteTodo(id!);

    final afterDelete = await repo.watchTodos().first;
    expect(afterDelete.any((t) => t.id == id), isFalse,
        reason: '软删后不应再出现在列表流里');

    final row = await (db.select(db.todos)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(row.deleted, isTrue, reason: '删除一律软删（§4.3 红线）：行必须还在');
    expect(row.version, greaterThan(1), reason: '软删是一次 update，version 应递增');

    await actions.restoreTodo(id);
    final afterUndo = await repo.watchTodos().first;
    expect(afterUndo.any((t) => t.id == id), isTrue,
        reason: '撤销删除后应回到列表');
  });

  testWidgets('④ UI：录入一行后列表多一条，空态消失', (tester) async {
    final container = containerOf();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: StudyPage()),
      ),
    );
    await settle(tester);

    // 初始是引导式空态：文案指向上方输入框，而不是「某版本上线后」
    expect(find.text('还没有安排学习任务'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);

    await tester.enterText(find.byType(TextField), '整理错题本');
    await settle(tester);
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);

    expect(find.byType(Checkbox), findsOneWidget, reason: '录入后列表应多出一条');
    expect(find.text('还没有安排学习任务'), findsNothing, reason: '有数据后空态应让位');
    expect(find.text('整理错题本'), findsWidgets);

    await drain(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
