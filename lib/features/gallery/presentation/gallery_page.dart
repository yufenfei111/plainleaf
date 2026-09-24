import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/skeleton.dart';
import '../domain/entities/gallery_asset.dart';
import 'photo_viewer_page.dart';
import 'providers/gallery_providers.dart';

/// 相册 Tab（W6：月分组网格 + 缩略图 + 分页）
///
/// 性能取舍（对应"滑动要丝滑"）：
/// - 网格只渲染 thumb（长边 400），并按格子尺寸×DPR 设 cacheWidth，
///   不让引擎解码原图——原图解码是掉帧主因；
/// - 用 CustomScrollView + SliverGrid 而不是嵌 GridView(shrinkWrap)，
///   避免嵌套滚动带来的重复布局计算；
/// - 分页：首屏 60 张，滚到距底 500px 续拉，长列表不一次性进内存。
class GalleryPage extends ConsumerStatefulWidget {
  const GalleryPage({super.key});

  @override
  ConsumerState<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends ConsumerState<GalleryPage> {
  final _scroll = ScrollController();
  static const double _cellSize = 116;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels < 500) {
      ref.read(galleryProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// 长按菜单：保留「看所属记录」这一条通路
  ///
  /// 为什么是菜单而不是长按直接跳：点图片想看的是图片本身（单击已交给全屏浏览），
  /// 跳详情变成了低频需求；放在菜单里给个可见入口，既不需要做多选题，
  /// 也避免「长按一下就被弹走」这种没有确认感的跳转。
  Future<void> _showEntryMenu(BuildContext context, int? entryId) async {
    if (entryId == null) return;
    // 要在 await 之后导航，先把导航对象握在手里，别跨异步再用 context
    final router = GoRouter.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('查看所属记录'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                router.push('/detail?id=$entryId');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncAssets = ref.watch(galleryProvider);
    final root = ref.watch(supportDirProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('相册'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => ref.read(galleryProvider.notifier).refresh(),
          ),
        ],
      ),
      body: asyncAssets.when(
        loading: () => const GridSkeleton(crossAxisCount: 3),
        error: (error, _) => _ErrorView(error: '$error'),
        data: (assets) {
          if (assets.isEmpty) {
            return const EmptyState(
              icon: Icons.photo_library_outlined,
              title: '还没有图片',
              subtitle: '在记录里拍照或选图，会汇总到这里',
            );
          }
          final groups = _groupByMonth(assets);
          final notifier = ref.watch(galleryProvider.notifier);
          final hasMore = notifier.hasMore;
          final loadMoreError = notifier.loadMoreError;
          return RefreshIndicator(
            onRefresh: () => ref.read(galleryProvider.notifier).refresh(),
            child: CustomScrollView(
            controller: _scroll,
            // 下拉刷新在空内容时也要可用：physics 必须始终可拉伸，
            // 否则数据量不足一屏时 RefreshIndicator 拉不出来。
            physics: const AlwaysScrollableScrollPhysics(),
            scrollCacheExtent: const ScrollCacheExtent.viewport(1.0),
            slivers: [
              for (final g in groups) ...[
                SliverToBoxAdapter(child: _MonthHeader(label: g.label)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _GridTile(
                        asset: g.items[i],
                        root: root,
                        size: _cellSize,
                        // W11：点图 = 原地铺开看图；「进所属记录」退居长按菜单。
                        // 之前点图直接跳详情是为了让格子「点得动」的过渡方案，
                        // 但用户点一张照片想看的是这张照片，不是它背后的那篇记录。
                        onTap: root == null
                            ? null
                            : () => PhotoViewerPage.open(
                                  context,
                                  assets: assets,
                                  index: g.start + i,
                                  supportDir: root,
                                ),
                        onLongPress: () =>
                            _showEntryMenu(context, g.items[i].entryId),
                      ),
                      childCount: g.items.length,
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: switch ((hasMore, loadMoreError)) {
                      // 续拉失败：保留已加载内容，只在这里给重试入口
                      (_, _?) => TextButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('加载失败，点击重试'),
                          onPressed: () =>
                              ref.read(galleryProvider.notifier).loadMore(),
                        ),
                      (true, _) => const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      _ => Text(
                          '共 ${assets.length} 张',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
            ),
          );
        },
      ),
    );
  }
}

/// 按"年月"分组（数据已按创建时间倒序，组内顺序天然正确）
///
/// [start] 记下本组首图在扁平列表里的下标：全屏浏览要按同一份顺序翻页，
/// 缺了它就没法把「点的是第几张」还原成跨月连续的页码。
List<_MonthGroup> _groupByMonth(List<GalleryAsset> assets) {
  final groups = <_MonthGroup>[];
  String? currentLabel;
  for (var i = 0; i < assets.length; i++) {
    final a = assets[i];
    final label = '${a.createdAt.year}年'
        '${a.createdAt.month.toString().padLeft(2, '0')}月';
    if (label != currentLabel) {
      currentLabel = label;
      groups.add(_MonthGroup(label, start: i));
    }
    groups.last.items.add(a);
  }
  return groups;
}

class _MonthGroup {
  _MonthGroup(this.label, {required this.start});
  final String label;

  /// 本组首图在扁平列表中的下标
  final int start;
  final List<GalleryAsset> items = [];
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.asset,
    required this.root,
    required this.size,
    required this.onTap,
    required this.onLongPress,
  });

  final GalleryAsset asset;
  final String? root;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final rel = asset.thumbPath ?? asset.relPath;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        // 碎图占位必须是「可点的」：图片加载失败时 Image 自身会塌成 0×0，
        // deferToChild 的默认行为会让整格丢失命中，用户点了没反应。
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: root == null
            // 支持目录还没解析出来（只有启动时那几十毫秒）：先占位，别拼空基准路径
            ? placeholder
            : Image.file(
                File(p.join(root!, rel)),
                fit: BoxFit.cover,
                cacheWidth: (size * dpr).round(),
                errorBuilder: (_, _, _) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text('相册加载失败', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
