import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'assets_dao.g.dart';

@DriftAccessor(tables: [Assets])
class AssetsDao extends DatabaseAccessor<PlainLeafDatabase>
    with _$AssetsDaoMixin {
  AssetsDao(super.db);

  /// 挂接媒体资产（W6：缩略图与元信息一并落库，避免二次查询）
  ///
  /// W17 多格式：`kind` 不再只有 'image'（见 `AssetKind`）；
  /// 新增 [mimeType] / [originalName] / [durationMs] 三个可选参数 ——
  /// 非图片文件必须带上**原始文件名**，否则列表里只剩一串 uuid。
  Future<int> attach({
    required String uuid,
    required int entryId,
    required String kind,
    required String relPath,
    String? thumbPath,
    String? mediumPath,
    String? mimeType,
    String? originalName,
    int? width,
    int? height,
    int? sizeBytes,
    int? durationMs,
    String? hashSha256,
  }) {
    return into(assets).insert(AssetsCompanion.insert(
      uuid: uuid,
      entryId: Value(entryId),
      kind: Value(kind),
      relPath: relPath,
      thumbPath: Value(thumbPath),
      mediumPath: Value(mediumPath),
      mimeType: Value(mimeType),
      originalName: Value(originalName),
      width: Value(width),
      height: Value(height),
      sizeBytes: Value(sizeBytes),
      durationMs: Value(durationMs),
      hashSha256: Value(hashSha256),
    ));
  }

  /// 回填派生图（缩略图管线是异步的：先落原图保证不阻塞，转码完再补字段）
  Future<void> updateDerived(
    int assetId, {
    String? thumbPath,
    String? mediumPath,
    int? width,
    int? height,
    int? sizeBytes,
    String? hashSha256,
  }) {
    return transaction(() async {
      final row =
          await (select(assets)..where((a) => a.id.equals(assetId))).getSingle();
      await (update(assets)..where((a) => a.id.equals(assetId))).write(
        AssetsCompanion(
          thumbPath: thumbPath != null ? Value(thumbPath) : const Value.absent(),
          mediumPath:
              mediumPath != null ? Value(mediumPath) : const Value.absent(),
          width: width != null ? Value(width) : const Value.absent(),
          height: height != null ? Value(height) : const Value.absent(),
          sizeBytes: sizeBytes != null ? Value(sizeBytes) : const Value.absent(),
          hashSha256:
              hashSha256 != null ? Value(hashSha256) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }

  /// 相册分页：按创建时间倒序（W6 网格滚动性能红线）
  Future<List<Asset>> pagedImages({required int limit, required int offset}) {
    return (select(assets)
          ..where((a) => a.deleted.equals(false) & a.kind.equals('image'))
          ..orderBy([
            (a) => OrderingTerm.desc(a.createdAt),
            (a) => OrderingTerm.desc(a.id),
          ])
          ..limit(limit, offset: offset))
        .get();
  }

  /// 缺缩略图的资产（W4 期落库的历史数据，供 backfill 补齐）
  Future<List<Asset>> missingThumb({int limit = 200}) {
    return (select(assets)
          ..where((a) =>
              a.deleted.equals(false) &
              a.kind.equals('image') &
              a.thumbPath.isNull())
          ..limit(limit))
        .get();
  }

  /// 未删除图片总数（分页上界）
  Future<int> countImages() {
    final count = assets.id.count();
    final q = selectOnly(assets)
      ..addColumns([count])
      ..where(assets.deleted.equals(false) & assets.kind.equals('image'));
    return q.map((row) => row.read(count) ?? 0).getSingle();
  }

  /// 条目下的图片资产（sortIndex 升序）
  Future<List<Asset>> byEntry(int entryId) {
    return (select(assets)
          ..where((a) =>
              a.entryId.equals(entryId) &
              a.deleted.equals(false) &
              a.kind.equals('image'))
          ..orderBy([(a) => OrderingTerm.asc(a.sortIndex)]))
        .get();
  }

  /// 软删除单个资产（文件不动；物理清理走回收站策略）
  Future<void> softDelete(int assetId) {
    return transaction(() async {
      final row =
          await (select(assets)..where((a) => a.id.equals(assetId))).getSingle();
      await (update(assets)..where((a) => a.id.equals(assetId))).write(
        AssetsCompanion(
          deleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }
}