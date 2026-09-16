import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'assets_dao.g.dart';

@DriftAccessor(tables: [Assets])
class AssetsDao extends DatabaseAccessor<PlainLeafDatabase>
    with _$AssetsDaoMixin {
  AssetsDao(super.db);

  /// 挂接媒体资产：同一事务内插入（version 语义由业务表统一约定）
  Future<int> attach({
    required String uuid,
    required int entryId,
    required String kind,
    required String relPath,
    int? sizeBytes,
  }) {
    return into(assets).insert(AssetsCompanion.insert(
      uuid: uuid,
      entryId: Value(entryId),
      kind: Value(kind),
      relPath: relPath,
      sizeBytes: Value(sizeBytes),
    ));
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