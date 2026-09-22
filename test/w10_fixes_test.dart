import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/editor/presentation/editor_page.dart';
import 'package:plainleaf/features/gallery/domain/entities/gallery_asset.dart';
import 'package:plainleaf/features/gallery/domain/repositories/gallery_repository.dart';
import 'package:plainleaf/features/gallery/presentation/providers/gallery_providers.dart';
import 'package:plainleaf/features/notebooks/presentation/notebooks_page.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/main.dart';

/// W10 自检修复的回归用例
///
/// 每一条都对应一个「用户能感知到的坏体验」，不是为覆盖率而写：
/// ① 编辑器改分类属性要能落库且可清空；
/// ② 未点「完成」就退出，最后 500ms 的输入不能丢；
/// ③ 新建笔记本后不能把整页弹走；
/// ④ 相册续拉失败不能把已加载的内容清空；
/// ⑤ 笔记本角标一次查询拿到全部计数。
void main() {
  late PlainLeafDatabase db;

  setUp(() async {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
  });

  tearDown(() async {
    // 用例 ④ 会主动关库制造失败，这里要容忍二次关闭
    try {
      await db.close();
    } on Object {
      // ignore
    }
  });

  test('① 分类属性：类型/笔记本/心情可写入，也可显式清空', () async {
    final repo = LocalTimelineRepository(db.entriesDao);
    final notebookId = await db.notebooksDao.create(
      uuid: const Uuid().v4(),
      name: '生活空间',
      space: 'life',
    );
    final id = await repo.saveEntry(
      const EntryDraft(title: '待归类', plainText: '正文'),
    );

    await repo.updateEntryMeta(
      id,
      type: EntryType.todo,
      notebookId: notebookId,
      mood: 4,
    );

    var row = await db.entriesDao.findById(id);
    expect(row!.type, 'todo');
    expect(row.notebookId, notebookId);
    expect(row.mood, 4);

    // 清空：不传值 + clear 开关 —— 三项都要能回到「未设置」
    await repo.updateEntryMeta(id, clearNotebook: true, clearMood: true);
    row = await db.entriesDao.findById(id);
    expect(row!.notebookId, isNull);
    expect(row.mood, isNull);
    expect(row.type, 'todo', reason: '未传 type 时不应被顺手清掉');

    // version 必须递增（乐观锁/同步的语义基础）
    expect(row.version, greaterThan(1));
  });

  testWidgets('② 未点完成就退出：最后一次输入仍要落库', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const EditorPage())],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    // 等 _bootstrap 落完草稿
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.enterText(find.byType(TextField).first, '未点完成的标题');
    // 故意不等 500ms 防抖：直接销毁页面（模拟用户/系统立刻回收）
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // 销毁后必须把时间推进完：FakeAsync 下残留的 timer（防抖/quill 内部）
    // 不 pump 就不会触发，测试结束时会因「timer 仍 pending」直接判失败。
    await tester.pump(const Duration(milliseconds: 600));

    // 数据库查询必须放在 runAsync 里：Widget 测试跑在 FakeAsync 下，
    // 不 pump 就不推进微任务，drift 的流永远不会 emit（会把用例挂死）。
    final titles = await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final drafts = await db.entriesDao.watchDrafts().first;
      return drafts.map((e) => e.title).toList();
    });

    expect(titles, contains('未点完成的标题'),
        reason: 'dispose 必须冲刷防抖，不能丢掉最后一次输入');
  });

  testWidgets('③ 新建笔记本后仍停留在笔记本页（不再被整页弹走）', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const NotebooksPage()),
        GoRoute(path: '/timeline', builder: (_, _) => const SizedBox.shrink()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 不用 pumpAndSettle：页面里有流的加载态与进度指示器，
    // 一旦某条流迟迟不来，settle 会等到超时而不是快速失败。
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).first, '读书笔记');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('创建'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NotebooksPage), findsOneWidget,
        reason: '对话框关闭不得再 pop 掉页面本身');
    expect(find.text('读书笔记'), findsOneWidget);

    // 收尾：销毁树并推进时间，清掉 drift watch / tooltip 等残留 timer，
    // 否则测试结束时的「Timer is still pending」断言会直接判失败。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  test('④ 相册续拉失败：保留已加载数据，只暴露错误', () async {
    // 用可失败的假仓库而不是关库制造错误：关闭后的 drift 查询可能永远 pending，
    // 会把测试挂死，而我们要验的是「出错时的状态处理」这一段逻辑。
    final container = ProviderContainer(overrides: [
      dbProvider.overrideWithValue(db),
      galleryRepositoryProvider.overrideWithValue(_FailOnSecondPageRepo()),
    ]);
    addTearDown(container.dispose);

    final first = await container.read(galleryProvider.future);
    expect(first.length, 60);

    await container.read(galleryProvider.notifier).loadMore();

    final state = container.read(galleryProvider);
    expect(state.hasError, isFalse, reason: '续拉失败不能把列表变成错误态');
    expect(state.valueOrNull, isNotNull);
    expect(state.valueOrNull!.length, 60, reason: '已加载的 60 张必须还在');
    expect(container.read(galleryProvider.notifier).loadMoreError, isNotNull);
  });

  test('⑤ 笔记本角标：一次 GROUP BY 拿到各本条目数', () async {
    final repo = LocalTimelineRepository(db.entriesDao);
    final lifeId = await db.notebooksDao.create(
      uuid: const Uuid().v4(),
      name: '生活',
      space: 'life',
    );
    final studyId = await db.notebooksDao.create(
      uuid: const Uuid().v4(),
      name: '学习',
      space: 'study',
    );
    final emptyId = await db.notebooksDao.create(
      uuid: const Uuid().v4(),
      name: '空本',
      space: 'custom',
    );

    for (var i = 0; i < 3; i++) {
      await repo.saveEntry(EntryDraft(
        title: '生活$i',
        plainText: 'p',
        notebookId: lifeId,
        status: EntryStatus.normal,
      ));
    }
    await repo.saveEntry(
      EntryDraft(title: '学习1', plainText: 'p', notebookId: studyId),
    );

    final counts = await db.notebooksDao.watchEntryCountsByNotebook().first;
    expect(counts[lifeId], 3);
    expect(counts[studyId], 1);
    expect(counts.containsKey(emptyId), isFalse,
        reason: '0 条的本不出现在 GROUP BY 结果里，UI 侧按 0 处理');
  });
}

/// 首屏返回满页（制造 hasMore=true），第二次续拉直接抛错的假仓库
class _FailOnSecondPageRepo implements GalleryRepository {
  int _calls = 0;

  @override
  Future<List<GalleryAsset>> page({required int limit, required int offset}) async {
    _calls++;
    if (_calls == 1) {
      return [
        for (var i = 0; i < limit; i++)
          GalleryAsset(
            id: i,
            entryId: 1,
            relPath: 'media/2026/09/$i.jpg',
            createdAt: DateTime(2026, 9, 1),
          ),
      ];
    }
    throw StateError('续拉失败（测试注入）');
  }

  @override
  Future<int> count() async => 65;
}
