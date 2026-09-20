import '../entities/gallery_asset.dart';

/// 相册仓库接口（features/gallery/domain）
/// UI 只依赖本接口（§4.2 分层红线）。
abstract interface class GalleryRepository {
  /// 分页取图片，按创建时间倒序
  Future<List<GalleryAsset>> page({required int limit, required int offset});

  /// 未删除图片总数（分页上界）
  Future<int> count();
}
