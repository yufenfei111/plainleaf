import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/media/image_saver.dart';
import '../../data/gallery_repository_impl.dart';
import '../../domain/entities/gallery_asset.dart';
import '../../domain/repositories/gallery_repository.dart';

final galleryRepositoryProvider = Provider<GalleryRepository>((ref) {
  return LocalGalleryRepository(ref.watch(dbProvider).assetsDao);
});

/// 图片保存器（W15 需求 3）
///
/// 测试必须 override 成 `RecordingImageSaver`：默认实现里 Android/iOS 走 `gal`
/// 平台通道、桌面走真实磁盘，在 `flutter test` 里两者都不该被触发。
final imageSaverProvider =
    Provider<ImageSaver>((ref) => defaultImageSaver());

/// 相册分页状态（W6 性能红线：一次只取一屏多一点，滚动到底再续）
/// 用 AsyncNotifier 承载：首屏 AsyncLoading → AsyncData，加载更多时保留已有数据。
class GalleryNotifier extends AsyncNotifier<List<GalleryAsset>> {
  static const int pageSize = 60;

  bool _hasMore = true;
  bool _loading = false;
  Object? _loadMoreError;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _loading;

  /// 续拉失败的原因（W10 修复）
  ///
  /// 原实现在续拉出错时把 state 整个置成 AsyncError：页面立刻从「已滑到第 300 张」
  /// 变成一张错误页，**已加载的数据全丢**。续拉失败只是「下一页没取到」，
  /// 不该推翻已经握在手里的结果——改为保留数据 + 单独暴露错误供底部重试。
  Object? get loadMoreError => _loadMoreError;

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
    final current = state.valueOrNull ?? const <GalleryAsset>[];
    try {
      final more = await ref
          .read(galleryRepositoryProvider)
          .page(limit: pageSize, offset: current.length);
      _hasMore = more.length >= pageSize;
      _loadMoreError = null;
      state = AsyncData([...current, ...more]);
    } on Object catch (error) {
      // 保留已加载的数据，只把错误单独透出（页面底部给重试入口）
      _loadMoreError = error;
      state = AsyncData(current);
    } finally {
      _loading = false;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    _loadMoreError = null;
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
