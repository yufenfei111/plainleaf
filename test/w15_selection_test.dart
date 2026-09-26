import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_filter.dart';
import 'package:plainleaf/features/timeline/presentation/providers/note_selection.dart';
import 'package:plainleaf/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:plainleaf/features/timeline/presentation/timeline_page.dart';

/// W15 需求 2：笔记多选 + 按条件筛选批量选择
///
/// 数据层用例跑真实内存库（含 FTS 双写），状态层用 ProviderContainer，
/// 页面层只验"入口 → 工具条 → 退出"这条骨架（卡片交互另有既有回归覆盖）。
final Directory _root = Directory.systemTemp.createTempSync('plainleaf_w15');

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePaths(_root.path);
  });

  group('数据层：批量操作', () {
    late PlainLeafDatabase db;
    late LocalTimelineRepository repo;

    setUp(() {
      db = PlainLeafDatabase.forTesting(openInMemoryDb());
      repo = LocalTimelineRepository(db.entriesDao);
    });

    tearDown(() async {
      try {
        await db.close();
      } on Object {
        // 容忍二次关闭
      }
    });

    test('① 按筛选取全部 id：不受时间轴分页 limit 限制', () async {
      for (var i = 0; i < 5; i++) {
        await repo.saveEntry(
          EntryDraft(title: '笔记$i', plainText: '内容$i', type: EntryType.note),
        );
      }
      for (var i = 0; i < 3; i++) {
        await repo.saveEntry(
          EntryDraft(title: '日记$i', plainText: '日记$i', type: EntryType.diary),
        );
      }

      final all = await repo.selectIdsByFilter();
      expect(all.length, 8);

      final diaries = await repo.selectIdsByFilter(
        filter: const TimelineFilter(type: EntryType.diary),
      );
      expect(diaries.length, 3);

      // 这一条是本用例的核心：时间轴受 limit 限制，而"全选"必须拿到全部。
      // 若两者搞混，用户会以为全选了、实际漏掉看不见的那部分。
      final page = await repo.watchTimeline(limit: 4).first;
      expect(page.length, 4);
      expect(all.length, greaterThan(page.length));
    });

    test('② 批量软删：条数正确、FTS 同步清理、行进回收站', () async {
      final ids = <int>[];
      for (var i = 0; i < 4; i++) {
        ids.add(await repo.saveEntry(
          EntryDraft(title: '待删$i', plainText: '内容$i'),
        ));
      }
      expect(await db.entriesDao.searchEntryIds('待删*'), isNotEmpty);

      final removed = await repo.softDeleteMany(ids.take(3).toList());
      expect(removed, 3);

      // 索引与数据必须一致：留下的那条搜得到，删掉的三条搜不到
      final remaining = await db.entriesDao.searchEntryIds('待删*');
      expect(remaining.length, 1);
      expect(remaining.single, ids.last);

      // 数据红线：是软删——行还在，回收站里能看到
      final trash = await repo.watchTrash().first;
      expect(trash.length, 3);
    });

    test('③ 批量软删幂等：重复删同一批不会重复计数', () async {
      final id = await repo.saveEntry(const EntryDraft(title: 'A', plainText: 'a'));
      expect(await repo.softDeleteMany(<int>[id]), 1);
      expect(await repo.softDeleteMany(<int>[id]), 0,
          reason: '已删除的 id 应被跳过');
    });

    test('④ 空列表是安全的空操作（不开启事务、不抛错）', () async {
      expect(await repo.softDeleteMany(const <int>[]), 0);
      expect(await repo.setPinnedMany(const <int>[], pinned: true), 0);
    });

    test('⑤ 批量置顶 / 取消置顶', () async {
      final ids = <int>[];
      for (var i = 0; i < 3; i++) {
        ids.add(await repo.saveEntry(
          EntryDraft(title: '置顶$i', plainText: ''),
        ));
      }

      expect(await repo.setPinnedMany(ids, pinned: true), 3);
      var rows = await db.select(db.entries).get();
      expect(rows.where((e) => e.pinned).length, 3);

      expect(await repo.setPinnedMany(ids, pinned: false), 3);
      rows = await db.select(db.entries).get();
      expect(rows.where((e) => e.pinned), isEmpty);
    });
  });

  group('状态层：多选', () {
    test('⑥ 进入 / 切换 / 全选 / 退出', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(noteSelectionProvider.notifier);

      expect(container.read(noteSelectionProvider).active, isFalse);

      notifier.enter();
      expect(container.read(noteSelectionProvider).active, isTrue);
      expect(container.read(noteSelectionProvider).count, 0);

      notifier.toggle(7);
      notifier.toggle(9);
      expect(container.read(noteSelectionProvider).ids, {7, 9});

      notifier.toggle(7);
      expect(container.read(noteSelectionProvider).ids, {9}, reason: '再点一次取消');

      notifier.selectAll(<int>[1, 2, 3]);
      expect(container.read(noteSelectionProvider).count, 3,
          reason: '按筛选全选是替换式，不是追加');

      notifier.clearAll();
      expect(container.read(noteSelectionProvider).count, 0);
      expect(container.read(noteSelectionProvider).active, isTrue,
          reason: '清空已选但仍在选择模式下');

      notifier.exit();
      expect(container.read(noteSelectionProvider).active, isFalse);
    });

    test('⑦ 筛选条件一变，已选立即清空（安全约束）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(noteSelectionProvider.notifier).start(1);
      expect(container.read(noteSelectionProvider).count, 1);

      // 换筛选：若不清空，用户随后点删除会删掉屏幕上已看不见的记录
      container.read(timelineFilterProvider.notifier).state =
          const TimelineFilter(type: EntryType.diary);

      expect(container.read(noteSelectionProvider).count, 0);
      expect(container.read(noteSelectionProvider).active, isFalse);
    });
  });

  group('页面：多选入口与工具条', () {
    testWidgets('⑧ 点「多选」出现工具条，点 ✕ 退出并恢复筛选条', (tester) async {
      final db = PlainLeafDatabase.forTesting(openInMemoryDb());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: const MaterialApp(home: TimelinePage()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('enter-selection')), findsOneWidget);

      await tester.tap(find.byKey(const Key('enter-selection')));
      await tester.pump();

      expect(find.text('点卡片选择记录'), findsOneWidget);
      expect(find.byKey(const Key('selection-select-all')), findsOneWidget);
      expect(find.byKey(const Key('selection-exit')), findsOneWidget);

      await tester.tap(find.byKey(const Key('selection-exit')));
      await tester.pump();

      expect(find.byKey(const Key('enter-selection')), findsOneWidget);
      expect(find.byKey(const Key('selection-exit')), findsNothing);

      // 主动卸载并推进一帧：drift 的 QueryStream 关闭时会排一个 0ms 定时器
      // （StreamQueryStore.markAsClosed）。留到用例结束的话，flutter_test 会报
      // "A Timer is still pending even after the widget tree was disposed" ——
      // 这不是产品代码的问题，是测试必须把事件循环推干净。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
