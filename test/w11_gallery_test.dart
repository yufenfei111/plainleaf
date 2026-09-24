import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/gallery/domain/entities/gallery_asset.dart';
import 'package:plainleaf/features/gallery/domain/repositories/gallery_repository.dart';
import 'package:plainleaf/features/gallery/presentation/gallery_page.dart';
import 'package:plainleaf/features/gallery/presentation/photo_viewer_page.dart';
import 'package:plainleaf/features/gallery/presentation/providers/gallery_providers.dart';
import 'package:plainleaf/main.dart';

/// W11 相册全屏浏览回归用例
///
/// 三条各对契约里的一条承诺：
/// ① 看图的取图序列是 thumb → medium → 原图，且不重复解码同一路径；
/// ② 仓库返回不足一页时判定「已经到底」（首屏 60 与续拉失败另有用例覆盖，不重复）；
/// ③ 点网格打开全屏浏览，初始下标 = 所点图片的位置——不再是「跳详情」。
///
/// 两条纪律（沿用既有测试）：
/// - provider 语义一律用 ProviderContainer 直测，不进 Widget 树；
/// - 全程**不用 pumpAndSettle**：drift 流与图片解码都可能在 settle 里等到超时，
///   这里只用有界的 pump 循环。
void main() {
  late PlainLeafDatabase db;

  setUp(() => db = PlainLeafDatabase.forTesting(openInMemoryDb()));
  tearDown(() => db.close());

  test('① 取图序列：thumb → medium → 原图，重复路径只留一份', () {
    final full = GalleryAsset(
      id: 1,
      entryId: 1,
      relPath: 'media/a.jpg',
      thumbPath: 'thumb/a.jpg',
      mediumPath: 'medium/a.jpg',
      createdAt: DateTime(2026, 9, 1),
    );
    expect(
      viewerImageStages(full),
      <String>['thumb/a.jpg', 'medium/a.jpg', 'media/a.jpg'],
      reason: '必须由粗到细，细一级加载完再顶掉粗一级',
    );

    // 历史数据未回填缩略图：只能一级到位，且只有一条
    final legacy = GalleryAsset(
      id: 2,
      entryId: 1,
      relPath: 'media/b.jpg',
      createdAt: DateTime(2026, 9, 1),
    );
    expect(viewerImageStages(legacy), <String>['media/b.jpg']);

    // thumb 指回原图（回填失败的历史数据）：折叠成一条，避免同一个文件解码两次
    final duplicated = GalleryAsset(
      id: 3,
      entryId: 1,
      relPath: 'media/c.jpg',
      thumbPath: 'media/c.jpg',
      createdAt: DateTime(2026, 9, 1),
    );
    expect(viewerImageStages(duplicated), <String>['media/c.jpg']);
  });

  test('② 首屏不足一页时判定「已经到底」', () async {
    final container = ProviderContainer(
      overrides: [
        galleryRepositoryProvider.overrideWithValue(_ShortPageRepo()),
      ],
    );
    addTearDown(container.dispose);

    final first = await container.read(galleryProvider.future);
    expect(first.length, 2);
    expect(container.read(galleryProvider.notifier).hasMore, isFalse,
        reason: '结果不足 pageSize，不应再续拉');

    // 已经到底后再调 loadMore：不应把状态弄乱（数据还是那 2 条）
    await container.read(galleryProvider.notifier).loadMore();
    expect(container.read(galleryProvider).valueOrNull!.length, 2);
  });

  testWidgets('③ 点网格进全屏浏览：打开 PhotoViewerPage 并停在所点的那张',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const GalleryPage()),
        GoRoute(path: '/detail', builder: (_, _) => const SizedBox.shrink()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          // 真实素材成本高：这里只需要「相对路径能拼成绝对路径」，
          // 文件不存在会走碎图标位，不影响「点格子 → 进看图」这条链路。
          supportDirProvider.overrideWith((ref) async => supportRoot),
          galleryRepositoryProvider.overrideWithValue(_ThreeAssetsRepo()),
        ],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
    // 有界落定：有界的 pump 循环，不用 pumpAndSettle
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(Image), findsNWidgets(3), reason: '三张图都应进入网格');

    // 点第 2 张：验证初始下标来自「这张图在扁平列表里的位置」
    await tester.tap(find.byType(Image).at(1));
    // 一次 pump(300) 不够：push 是在 tap 的下一帧才 install，
    // 再叠 200ms 淡入，必须多推一帧才能拿到已挂载的看图页。
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PhotoViewerPage), findsOneWidget,
        reason: '点网格应打开全屏浏览，不再是跳详情');
    expect(find.text('2/3'), findsOneWidget,
        reason: '初始下标应是所点图片的下标（1-based 展示为 2/3）');

    // 关闭按钮 ≥44dp 且能真的退回去
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PhotoViewerPage), findsNothing);

    // 收尾：卸载树并推进时间，清掉 drift 与 tooltip 的残留 timer
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// UI 用例用的支持目录：只需要一个能把相对路径拼成绝对路径的字符串，
/// 底下不放真实文件（见用例里的注释）。
const String supportRoot = '/tmp/plainleaf-w11-viewer';

/// 只返回 2 条的假仓库：用来验「不足一页 = 已经到底」
class _ShortPageRepo implements GalleryRepository {
  @override
  Future<List<GalleryAsset>> page({
    required int limit,
    required int offset,
  }) async =>
      [
        for (var i = 0; i < 2; i++)
          GalleryAsset(
            id: i,
            entryId: 1,
            relPath: 'media/$i.jpg',
            thumbPath: 'thumb/$i.jpg',
            mediumPath: 'medium/$i.jpg',
            createdAt: DateTime(2026, 9, 1),
          ),
      ];

  @override
  Future<int> count() async => 2;
}

/// 返回 3 条的假仓库（UI 用例的网格素材）：同一天 → 落在同一个月份分组里，
/// 所以网格里的第 N 张就是扁平列表里的第 N 个。
class _ThreeAssetsRepo implements GalleryRepository {
  @override
  Future<List<GalleryAsset>> page({
    required int limit,
    required int offset,
  }) async =>
      [
        for (var i = 0; i < 3; i++)
          GalleryAsset(
            id: i,
            entryId: 10 + i,
            relPath: 'media/$i.jpg',
            thumbPath: 'thumb/$i.jpg',
            mediumPath: 'medium/$i.jpg',
            createdAt: DateTime(2026, 9, 1),
          ),
      ];

  @override
  Future<int> count() async => 3;
}
