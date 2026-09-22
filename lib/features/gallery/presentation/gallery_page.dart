import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../domain/entities/gallery_asset.dart';
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
        loading: () => const Center(child: CircularProgressIndicator()),
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
                        onTap: () {
                          final entryId = g.items[i].entryId;
                          if (entryId == null) return;
                          // 相册里的图此前点不动；点开所属记录详情才是用户预期
                          context.push('/detail?id=$entryId');
                        },
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
List<_MonthGroup> _groupByMonth(List<GalleryAsset> assets) {
  final groups = <_MonthGroup>[];
  String? currentLabel;
  for (final a in assets) {
    final label = '${a.createdAt.year}年'
        '${a.createdAt.month.toString().padLeft(2, '0')}月';
    if (label != currentLabel) {
      currentLabel = label;
      groups.add(_MonthGroup(label));
    }
    groups.last.items.add(a);
  }
  return groups;
}

class _MonthGroup {
  _MonthGroup(this.label);
  final String label;
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
  });

  final GalleryAsset asset;
  final String? root;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rel = asset.thumbPath ?? asset.relPath;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: root == null
          ? placeholder
          : GestureDetector(
              onTap: onTap,
              child: Image.file(
                File(p.join(root!, rel)),
                fit: BoxFit.cover,
                cacheWidth: (size * dpr).round(),
                errorBuilder: (_, _, _) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
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
