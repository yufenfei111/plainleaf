import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/db/daos/assets_dao.dart';
import '../../../core/db/daos/entries_dao.dart';
import '../../../core/db/database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/media/thumbnail_pipeline.dart';
import '../../../core/storage/media_storage.dart';
import '../domain/entities/timeline_entry.dart';
import '../domain/repositories/timeline_repository.dart';

/// [TimelineRepository] 的本地 Drift 实现。
/// 一致性：所有写操作走 DAO 事务原语（含 FTS 双写）；DAO 异常在调用点统一
/// 包装为 [DatabaseException]（错误三层透传第一层）。
class LocalTimelineRepository implements TimelineRepository {
  LocalTimelineRepository(
    this._dao, {
    this.assetsDao,
    MediaStorage? mediaStorage,
  })  : _media = mediaStorage ?? MediaStorage();

  final EntriesDao _dao;

  /// 附件能力依赖（可空注入：未注入则 attach/first 路径不可用）
  final AssetsDao? assetsDao;
  final MediaStorage _media;

  @override
  Stream<List<TimelineEntry>> watchTimeline({int limit = 100}) {
    return _dao
        .watchTimeline(limit: limit)
        .map((rows) => rows.map(_rowToEntity).toList(growable: false));
  }

  @override
  Future<int> saveEntry(EntryDraft draft) async {
    try {
      return await _dao.saveEntry(
        entry: EntriesCompanion.insert(
          uuid: const Uuid().v4(),
          notebookId: Value(draft.notebookId),
          type: Value(draft.type.name),
          status: Value(draft.status.name),
          title: Value(draft.title),
          plainText: Value(draft.plainText),
          contentDelta: Value(draft.contentDelta),
          mood: Value(draft.mood),
          entryDate: Value(draft.entryDate ?? DateTime.now()),
        ),
        ftsTitle: draft.title,
        ftsContent: draft.plainText,
      );
    } on Exception catch (error) {
      throw DatabaseException('保存记录失败', cause: error);
    }
  }

  @override
  Future<void> updateEntry(int id, EntryDraft draft) async {
    try {
      await _dao.updateEntryContent(
        id,
        title: draft.title,
        plainText: draft.plainText,
        contentDelta: draft.contentDelta,
        ftsTitle: draft.title,
        ftsContent: draft.plainText,
      );
    } on Exception catch (error) {
      throw DatabaseException('更新记录失败', cause: error);
    }
  }

  @override
  Future<void> softDelete(int id) async {
    try {
      await _dao.softDelete(id);
    } on Exception catch (error) {
      throw DatabaseException('删除记录失败', cause: error);
    }
  }

  @override
  Future<void> restore(int id) async {
    try {
      await _dao.restore(id);
    } on Exception catch (error) {
      throw DatabaseException('恢复记录失败', cause: error);
    }
  }

  @override
  Future<List<int>> searchIds(String keywords) async {
    try {
      return await _dao.searchEntryIds(keywords);
    } on Exception catch (error) {
      throw DatabaseException('搜索失败', cause: error);
    }
  }

  @override
  Stream<List<TimelineEntry>> watchDrafts() =>
      _dao.watchDrafts().map(_rowsToEntities);

  @override
  Stream<List<TimelineEntry>> watchTrash() =>
      _dao.watchTrash().map(_rowsToEntities);

  @override
  Future<void> setStatus(int id, {required String status}) async {
    try {
      await _dao.setStatus(id, status: status);
    } on Exception catch (error) {
      throw DatabaseException('更新状态失败', cause: error);
    }
  }

  @override
  Future<void> setPinned(int id, {required bool pinned}) async {
    try {
      await _dao.setPinned(id, pinned: pinned);
    } on Exception catch (error) {
      throw DatabaseException('置顶操作失败', cause: error);
    }
  }

  @override
  Future<int> purgeExpiredTrash({int retainDays = 30}) async {
    try {
      return await _dao.purgeExpiredTrash(retainDays: retainDays);
    } on Exception catch (error) {
      throw DatabaseException('清理回收站失败', cause: error);
    }
  }

  // ── 内部 ──────────────────────────────────────────────────────────

  List<TimelineEntry> _rowsToEntities(List<Entry> rows) =>
      rows.map(_entryToEntity).toList(growable: false);

  /// 草稿/回收站行没有联表数据；notebook 字段留空，列表页只展示内容本身
  TimelineEntry _entryToEntity(Entry e) {
    return TimelineEntry(
      id: e.id,
      uuid: e.uuid,
      title: e.title,
      plainText: e.plainText,
      type: EntryType.fromName(e.type),
      status: EntryStatus.fromName(e.status),
      pinned: e.pinned,
      entryDate: e.entryDate,
      mood: e.mood,
      notebookId: e.notebookId,
    );
  }

  /// 挂接图片（W6：原图入库 + 两级缩略图转码）
  /// 顺序：先复制原图落库（保证用户立刻看到图），再在 isolate 里转码并回填
  /// thumb/medium 与宽高、sha256。转码失败不回滚资产——原图仍在，
  /// 列表回退原图显示，后续可重跑 `backfillDerived()` 补齐。
  @override
  Future<int> attachImage(int entryId, String sourcePath) async {
    final dao = assetsDao;
    if (dao == null) {
      throw const DatabaseException('AssetsDao 未注入，无法挂接图片');
    }
    int assetId;
    String rel;
    try {
      rel = await _media.importFile(sourcePath);
      assetId = await dao.attach(
        uuid: const Uuid().v4(),
        entryId: entryId,
        kind: 'image',
        relPath: rel,
      );
    } on Exception catch (error) {
      throw DatabaseException('挂接图片失败', cause: error);
    }
    await _derive(dao, assetId, rel);
    return assetId;
  }

  /// 生成两级缩略图并回填（转码在 isolate，失败只降级不抛）
  Future<void> _derive(AssetsDao dao, int assetId, String originalRel) async {
    try {
      final base = p.basenameWithoutExtension(originalRel);
      final ext = p.extension(originalRel);
      final thumbRel = _media.newRelPath(
        MediaKind.thumb, '${base}_t', ext.isEmpty ? '.jpg' : ext);
      final mediumRel = _media.newRelPath(
        MediaKind.medium, '${base}_m', ext.isEmpty ? '.jpg' : ext);

      final originalAbs = (await _media.resolve(originalRel)).path;
      final thumbAbs = (await _media.resolve(thumbRel)).path;
      final mediumAbs = (await _media.resolve(mediumRel)).path;

      final derived = await ThumbnailPipeline().generate(
        sourceAbs: originalAbs,
        thumbAbs: thumbAbs,
        mediumAbs: mediumAbs,
        thumbRel: thumbRel,
        mediumRel: mediumRel,
      );
      await dao.updateDerived(
        assetId,
        thumbPath: derived.thumbRel,
        mediumPath: derived.mediumRel,
        width: derived.width,
        height: derived.height,
        sizeBytes: derived.sizeBytes,
        hashSha256: derived.hashSha256,
      );
    } on Object {
      // 降级：保留原图，等待 backfillDerived 重跑。
      // 这里必须连 Error 一起兜——损坏图片的解码器抛的是 RangeError，
      // 只 catch Exception 会让"挂一张坏图"直接把流程打断。
    }
  }

  /// 补齐历史资产的缩略图（W4 期落库的图没有 thumb；W6 后可一键补齐）
  @override
  Future<int> backfillDerived({int limit = 200}) async {
    final dao = assetsDao;
    if (dao == null) return 0;
    var done = 0;
    final rows = await dao.missingThumb(limit: limit);
    for (final a in rows) {
      await _derive(dao, a.id, a.relPath);
      done++;
    }
    return done;
  }

  @override
  Future<String?> firstImagePath(int entryId) async {
    final dao = assetsDao;
    if (dao == null) return null;
    try {
      final list = await dao.byEntry(entryId);
      if (list.isEmpty) return null;
      final f = await _media.resolve(list.first.relPath);
      return f.existsSync() ? list.first.relPath : null;
    } on Exception catch (error) {
      throw DatabaseException('读取图片失败', cause: error);
    }
  }

  TimelineEntry _rowToEntity(TimelineRow row) {
    final entry = row.entry;
    return TimelineEntry(
      id: entry.id,
      uuid: entry.uuid,
      title: entry.title,
      plainText: entry.plainText,
      type: EntryType.fromName(entry.type),
      status: EntryStatus.fromName(entry.status),
      pinned: entry.pinned,
      entryDate: entry.entryDate,
      mood: entry.mood,
      notebookId: entry.notebookId,
      notebookName: row.notebook?.name,
      notebookSpace: row.notebook?.space,
      firstAssetRelPath: row.firstAsset?.relPath,
      firstAssetThumbPath: row.firstAsset?.thumbPath,
    );
  }
}