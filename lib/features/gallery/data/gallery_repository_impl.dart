import '../../../../core/db/daos/assets_dao.dart';
import '../../../../core/errors/app_exception.dart';
import '../domain/entities/gallery_asset.dart';
import '../domain/repositories/gallery_repository.dart';

/// [GalleryRepository] 的本地 Drift 实现（W6）
/// 与其他 Repository 一致：异常统一包装为 [DatabaseException]。
class LocalGalleryRepository implements GalleryRepository {
  LocalGalleryRepository(this._dao);

  final AssetsDao _dao;

  @override
  Future<List<GalleryAsset>> page({
    required int limit,
    required int offset,
  }) async {
    try {
      final rows = await _dao.pagedImages(limit: limit, offset: offset);
      return rows
          .map((a) => GalleryAsset(
                id: a.id,
                entryId: a.entryId,
                relPath: a.relPath,
                thumbPath: a.thumbPath,
                mediumPath: a.mediumPath,
                createdAt: a.createdAt,
              ))
          .toList(growable: false);
    } on Exception catch (error) {
      throw DatabaseException('读取相册失败', cause: error);
    }
  }

  @override
  Future<int> count() async {
    try {
      return await _dao.countImages();
    } on Exception catch (error) {
      throw DatabaseException('统计图片失败', cause: error);
    }
  }
}
