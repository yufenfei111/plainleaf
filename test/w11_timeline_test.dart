import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:plainleaf/features/timeline/presentation/timeline_page.dart';
import 'package:plainleaf/main.dart';

/// W11 时间轴改造回归用例
///
/// 三条各对应契约里的一条承诺，不是为覆盖率而写：
/// ① 首屏只取 40 条，且判定「可能还有更多」；
/// ② 拉到末页后判定「已经到底」；
/// ③ 「筛选」入口能把 pinnedOnly 写进 timelineFilterProvider。
///
/// 两条纪律（踩过坑才定下来的）：
/// - ①② 直接驱动 ProviderContainer，不进 Widget 树——分页是 provider 层语义，
///   用 container 测既快又不受 RenderFlex / 动画时序影响；
/// - 全程**不用 pumpAndSettle**：时间轴是 StreamProvider，加载态会让 settle
///   等到超时而不是快速失败，这里一律用有界的 pump 循环。
void main() {
  late PlainLeafDatabase db;

  setUp(() => db = PlainLeafDatabase.forTesting(openInMemoryDb()));
  tearDown(() => db.close());

  /// 插入 count 条已发布记录（分页断言的素材）
  Future<void> seed(int count) async {
    final repo = LocalTimelineRepository(db.entriesDao);
    for (var i = 0; i < count; i++) {
      await repo.saveEntry(
        EntryDraft(
          title: '记录$i',
          plainText: '正文$i',
          status: EntryStatus.normal,
        ),
      );
    }
  }

  /// 有界落定：最多 ~1 秒，落不定就放行——
  /// 时间轴是 StreamProvider，数据延迟到达不应阻塞断言。
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

  test('① 首屏只取 40 条，且判定「可能还有更多」', () async {
    await seed(45);
    final container = ProviderContainer(
      overrides: [dbProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final seen = <int>[];
    container.listen<AsyncValue<List<TimelineEntry>>>(
      timelineStreamProvider,
      (previous, next) {
        if (next.hasValue) seen.add(next.valueOrNull!.length);
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(seen.isNotEmpty, isTrue, reason: '流应至少 emit 一次');
    expect(seen.last, kTimelinePageSize, reason: '首屏只取一页');
    // 「还有更多」判定：本次结果长度 >= 当前 limit
    expect(seen.last >= container.read(timelineLimitProvider), isTrue,
        reason: '45 条数据取 40 条，应判定为可能还有更多');
  });

  test('② 拉到末页后判定「已经到底」', () async {
    await seed(45);
    final container = ProviderContainer(
      overrides: [dbProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final seen = <int>[];
    container.listen<AsyncValue<List<TimelineEntry>>>(
      timelineStreamProvider,
      (previous, next) {
        if (next.hasValue) seen.add(next.valueOrNull!.length);
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(seen.last, kTimelinePageSize);

    // 续拉一页：limit += 一页，流带着新 limit 重查
    container.read(timelineLimitProvider.notifier).state += kTimelinePageSize;
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(seen.last, 45, reason: '库里只有 45 条，末页应全部返回');
    expect(seen.last >= container.read(timelineLimitProvider), isFalse,
        reason: '结果不足 limit，应判定为已经到底');
  });

  testWidgets('③ 「筛选」入口把 pinnedOnly 写进 timelineFilterProvider',
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

    // 打开筛选弹层：横条已换成一个「筛选」入口
    await tester.tap(find.text('筛选'));
    await settle(tester);

    // 弹层是纵向的，先保证目标滚进可视区再点，避免被 9/16 高度裁掉
    await tester.ensureVisible(find.text('仅看置顶'));
    await tester.tap(find.text('仅看置顶'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.ensureVisible(find.text('查看结果'));
    await tester.tap(find.text('查看结果'));
    await settle(tester);

    expect(container.read(timelineFilterProvider).pinnedOnly, isTrue,
        reason: '弹层里打开「仅看置顶」并点「查看结果」后应落进 provider');
    expect(container.read(timelineLimitProvider), kTimelinePageSize,
        reason: '换了筛选条件应回到首屏条数');

    await drain(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
