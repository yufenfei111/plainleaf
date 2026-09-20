import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../data/gallery_repository_impl.dart';
import '../../domain/entities/gallery_asset.dart';
import '../../domain/repositories/gallery_repository.dart';

final galleryRepositoryProvider = Provider<GalleryRepository>((ref) {
  return LocalGalleryRepository(ref.watch(dbProvider).assetsDao);
});

/// 相册分页状态（W6 性能红线：一次只取一屏多一点，滚动到底再续）
/// 用 AsyncNotifier 承载：首屏 AsyncLoading → AsyncData，加载更多时保留已有数据。
class GalleryNotifier extends AsyncNotifier<List<GalleryAsset>> {
  static const int pageSize = 60;

  bool _hasMore = true;
  bool _loading = false;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _loading;

  @override
  Future<List<GalleryAsset>> build() async {
    _hasMore = true;
    final first = await ref
        .read(galleryRepositoryProvider)
        .page(limit: pageSize, offset: 0);
    _hasMore = first.length >= pageSize;
    return first;
  }

  /// 续拉下一页；已无更多或正在加载时直接返回，避免重复请求
  Future<void> loadMore() async {
    if (!_hasMore || _loading) return;
    _loading = true;
    try {
      final current = state.valueOrNull ?? const <GalleryAsset>[];
      final more = await ref
          .read(galleryRepositoryProvider)
          .page(limit: pageSize, offset: current.length);
      _hasMore = more.length >= pageSize;
      state = AsyncData([...current, ...more]);
    } on Exception catch (error, stack) {
      // 保留已加载的数据，只把错误透出（错误三层透传第二层）
      state = AsyncError(error, stack);
    } finally {
      _loading = false;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _hasMore = true;
      final first = await ref
          .read(galleryRepositoryProvider)
          .page(limit: pageSize, offset: 0);
      _hasMore = first.length >= pageSize;
      return first;
    });
  }
}

final galleryProvider =
    AsyncNotifierProvider<GalleryNotifier, List<GalleryAsset>>(
        GalleryNotifier.new);
