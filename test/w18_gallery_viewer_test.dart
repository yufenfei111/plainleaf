import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:plainleaf/features/gallery/domain/entities/gallery_asset.dart';
import 'package:plainleaf/features/gallery/presentation/photo_viewer_page.dart';

/// W18 相册全屏浏览：左右滑动切换、首尾边界、初始下标。
///
/// ## 背景（先说清楚，免得误判成"新写的功能"）
/// 翻页能力从 **W11 就有**：手写 `Listener` 直接推 `PageController`，
/// 因为 `InteractiveViewer` 在命中路径里更深、会在手势竞技场里赢走横向拖拽
/// （见 photo_viewer_page.dart 的注释）。但**它一直没有用例** ——
/// 也就是说，"能滑动"这件事从来没被机器验证过，全靠手测印象。
///
/// 所以这组用例的第一目的是**把它钉住**：任何后续改动（包括本轮加的预加载与引导）
/// 都不能在无人察觉的情况下把它弄坏。
///
/// 两条纪律沿用既有测试：
/// - 全程不用 `pumpAndSettle`（图片解码与动画可能让它等到超时），只用有界 pump 循环；
/// - 素材用真实存在的文件（1×1 PNG），避免 `Image.file` 抛错干扰手势链路。
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('plainleaf_w18_viewer');
  });

  /// 造 [count] 张真实存在的图片，返回对应的 GalleryAsset。
  ///
  /// thumb / medium 一律留空：一方面模拟 W4 期只有原图的历史数据，
  /// 另一方面正好覆盖「取图序列回退到原图」这条路径。
  List<GalleryAsset> makeAssets(int count) {
    final dir = Directory('${root.path}/media/2026/09')
      ..createSync(recursive: true);
    final png = img.encodePng(img.Image(width: 2, height: 2));
    final assets = <GalleryAsset>[];
    for (var i = 0; i < count; i++) {
      File('${dir.path}/$i.png').writeAsBytesSync(png);
      assets.add(GalleryAsset(
        id: i,
        entryId: 100 + i,
        relPath: 'media/2026/09/$i.png',
        createdAt: DateTime(2026, 9, 1),
      ));
    }
    return assets;
  }

  Future<void> pumpViewer(
    WidgetTester tester, {
    required List<GalleryAsset> assets,
    int initialIndex = 0,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PhotoViewerPage(
            // 强制新建 State：同一个测试里连续 pump 两次时，同类型 widget 会复用
            // 既有 State，initState 不再跑 → initialIndex 不会生效（③ 踩过）
            key: UniqueKey(),
            assets: assets,
            initialIndex: initialIndex,
            supportDir: root.path,
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 滑动并等落位动画走完（落位固定 200ms，给 320ms 留余量）
  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.drag(find.byType(PageView), Offset(dx, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('① 左滑翻到下一张，右滑翻回上一张', (tester) async {
    await pumpViewer(tester, assets: makeAssets(3));
    expect(find.text('1/3'), findsOneWidget);

    await swipe(tester, -320);
    expect(find.text('2/3'), findsOneWidget, reason: '左滑（手指向左）应翻到下一张');

    await swipe(tester, -320);
    expect(find.text('3/3'), findsOneWidget);

    await swipe(tester, 320);
    expect(find.text('2/3'), findsOneWidget, reason: '右滑应翻回上一张');
  });

  testWidgets('② 首尾边界：滑到头停在原地，不越界也不白屏', (tester) async {
    await pumpViewer(tester, assets: makeAssets(3));

    // 已在第一张，继续右滑
    await swipe(tester, 320);
    expect(find.text('1/3'), findsOneWidget, reason: '第一张再往右滑应停在原地');

    // 连滑到末尾
    await swipe(tester, -320);
    await swipe(tester, -320);
    expect(find.text('3/3'), findsOneWidget);

    // 已在最后一张，继续左滑
    await swipe(tester, -320);
    expect(find.text('3/3'), findsOneWidget, reason: '最后一张再往左滑应停在原地');
  });

  testWidgets('③ 初始下标：点第几张就从第几张开始', (tester) async {
    await pumpViewer(tester, assets: makeAssets(3), initialIndex: 2);
    expect(find.text('3/3'), findsOneWidget);

    await pumpViewer(tester, assets: makeAssets(3), initialIndex: 1);
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('④ 单张图片：左右滑都不动，不崩', (tester) async {
    await pumpViewer(tester, assets: makeAssets(1));
    expect(find.text('1/1'), findsOneWidget);

    await swipe(tester, -320);
    expect(find.text('1/1'), findsOneWidget);
    await swipe(tester, 320);
    expect(find.text('1/1'), findsOneWidget);
  });

  testWidgets('⑤ 操作引导：首次显示、动手即收，且不挡住滑动', (tester) async {
    PhotoViewerPage.resetHintForTest();
    await pumpViewer(tester, assets: makeAssets(3));

    expect(find.textContaining('左右滑动切换'), findsOneWidget,
        reason: '首次打开应给出可发现性提示 —— 这正是"缺交互"的真正症结');

    // 引导挂在屏幕上时照样能滑（IgnorePointer 没白加）
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('2/3'), findsOneWidget, reason: '引导绝不能挡住手势');
    expect(find.textContaining('左右滑动切换'), findsNothing,
        reason: '用户一动手，引导就该收起');
  });

  testWidgets('⑥ 同一进程内只提示一次，不变成骚扰', (tester) async {
    PhotoViewerPage.resetHintForTest();

    await pumpViewer(tester, assets: makeAssets(3));
    expect(find.textContaining('左右滑动切换'), findsOneWidget);

    // 整棵树换掉再重新打开，模拟"退出看图后再次进入"
    await tester.pumpWidget(const SizedBox());
    await pumpViewer(tester, assets: makeAssets(3));
    expect(find.textContaining('左右滑动切换'), findsNothing);
  });
}
