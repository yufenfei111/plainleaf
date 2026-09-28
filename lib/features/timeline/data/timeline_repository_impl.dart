import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/db/daos/assets_dao.dart';
import '../../../core/db/daos/entries_dao.dart';
import '../../../core/db/database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/media/asset_kind.dart';
import '../../../core/media/audio_metadata_probe.dart';
import '../../../core/media/mime_lookup.dart';
import '../../../core/media/thumbnail_pipeline.dart';
import '../../../core/storage/media_storage.dart';
import '../domain/entities/entry_asset.dart';
import '../domain/entities/timeline_entry.dart';
import '../domain/entities/timeline_filter.dart';
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
  Stream<List<TimelineEntry>> watchTimeline({
    int limit = 100,
    TimelineFilter filter = const TimelineFilter(),
  }) {
    return _dao
        .watchTimeline(
          limit: limit,
          notebookId: filter.notebookId,
          type: filter.type?.name,
          pinnedOnly: filter.pinnedOnly,
          attachmentKind: filter.attachmentKind?.name,
        )
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
  Future<void> updateEntryMeta(
    int id, {
    EntryType? type,
    int? notebookId,
    bool clearNotebook = false,
    int? mood,
    bool clearMood = false,
  }) async {
    try {
      await _dao.updateEntryMeta(
        id,
        type: type?.name,
        notebookId: clearNotebook
            ? const Value(null)
            : (notebookId == null ? const Value.absent() : Value(notebookId)),
        mood: clearMood
            ? const Value(null)
            : (mood == null ? const Value.absent() : Value(mood)),
      );
    } on Exception catch (error) {
      throw DatabaseException('更新记录属性失败', cause: error);
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
  Future<List<int>> selectIdsByFilter({
    TimelineFilter filter = const TimelineFilter(),
  }) async {
    try {
      return await _dao.selectIdsByFilter(
        notebookId: filter.notebookId,
        type: filter.type?.name,
        pinnedOnly: filter.pinnedOnly,
        attachmentKind: filter.attachmentKind?.name,
      );
    } on Exception catch (error) {
      throw DatabaseException('读取筛选结果失败', cause: error);
    }
  }

  @override
  Future<int> softDeleteMany(List<int> ids) async {
    try {
      return await _dao.softDeleteMany(ids);
    } on Exception catch (error) {
      throw DatabaseException('批量删除失败', cause: error);
    }
  }

  @override
  Future<int> setPinnedMany(List<int> ids, {required bool pinned}) async {
    try {
      return await _dao.setPinnedMany(ids, pinned: pinned);
    } on Exception catch (error) {
      throw DatabaseException('批量置顶失败', cause: error);
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

  @override
  Future<void> hardDelete(int id) async {
    try {
      await _dao.hardDelete(id);
    } on Exception catch (error) {
      throw DatabaseException('永久删除失败', cause: error);
    }
  }

  @override
  Future<int> emptyTrash() async {
    try {
      return await _dao.emptyTrash();
    } on Exception catch (error) {
      throw DatabaseException('清空回收站失败', cause: error);
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
      updatedAt: e.updatedAt,
      mood: e.mood,
      notebookId: e.notebookId,
    );
  }

  /// 挂接图片（W6）。与 [attachFile] 等价，保留旧名以免改动既有调用点与用例。
  @override
  Future<int> attachImage(int entryId, String sourcePath) =>
      attachFile(entryId, sourcePath);

  /// 挂接任意类型的文件（W17 多格式）
  ///
  /// 顺序：探测类型 → 复制原文件落库（保证用户立刻看到条目）→
  /// **仅图片**进 isolate 转码并回填 thumb/medium 与宽高、sha256。
  ///
  /// 转码失败不回滚资产 —— 原文件仍在，列表回退原图显示，
  /// 后续可重跑 `backfillDerived()` 补齐。
  @override
  Future<int> attachFile(int entryId, String sourcePath) async {
    final dao = assetsDao;
    if (dao == null) {
      throw const DatabaseException('AssetsDao 未注入，无法挂接文件');
    }

    // 探测放在复制之前：读的是来源文件，读不到也只会退化为按扩展名判断，不抛异常。
    final kind = AssetTypeDetector.detectFile(sourcePath);
    final originalName = p.basename(sourcePath);

    int assetId;
    String rel;
    int? sizeBytes;
    try {
      final source = File(sourcePath);
      // 大小必须在复制前取（复制后仍是同一个文件，但来源可能随后被删除）
      sizeBytes = source.existsSync() ? source.lengthSync() : null;
      rel = await _media.importFile(sourcePath);
      assetId = await dao.attach(
        uuid: const Uuid().v4(),
        entryId: entryId,
        kind: kind.name,
        relPath: rel,
        mimeType: mimeForFileName(originalName),
        originalName: originalName,
        sizeBytes: sizeBytes,
      );
    } on Exception catch (error) {
      throw DatabaseException('挂接文件失败', cause: error);
    }

    // 派生处理按类型分派：
    //   image → 两级缩略图（W6 线，行为不变）
    //   audio → 时长 + 内嵌封面（W20 P1-9）
    //   其余  → 没有可用的缩略图来源，thumbPath 保持 null（**null 是合法状态**，
    //           UI 走类型徽标）。视频抽帧与 PDF 首页渲染需要平台通道依赖，
    //           见计划文档的 P1-8 与 P2。
    if (kind == AssetKind.image) {
      await _derive(dao, assetId, rel);
    } else if (kind == AssetKind.audio) {
      await _deriveAudio(dao, assetId, rel);
    }
    return assetId;
  }

  /// 生成两级缩略图并回填（转码在 isolate，失败只降级不抛）
  ///
  /// [sourceAbs]：转码的输入文件。默认是原文件；**音频封面**走它传一张封面临时
  /// 文件 —— 封面是图，让同一套尺寸/质量控制把它压成两级缩略图，
  /// 比另写一套缩放逻辑可靠得多。
  ///
  /// [writeSourceMeta]：是否把**转码源**的宽高/字节数/hash 回写进资产行。
  /// 音频封面必须为 `false`：封面只是封面，不是资产本身 ——
  /// 把封面的字节数写成音频文件的大小，会让"文件大小"那一栏变成谎话。
  Future<void> _derive(
    AssetsDao dao,
    int assetId,
    String originalRel, {
    String? sourceAbs,
    bool writeSourceMeta = true,
  }) async {
    try {
      // 派生图总是跟着**原始资产**命名（不是跟着封面临时文件），
      // 否则清理临时文件后会留下一个意义不明的名字。
      final base = p.basenameWithoutExtension(originalRel);
      final ext = p.extension(originalRel);
      final thumbRel = _media.newRelPath(
        MediaKind.thumb, '${base}_t', ext.isEmpty ? '.jpg' : ext);
      final mediumRel = _media.newRelPath(
        MediaKind.medium, '${base}_m', ext.isEmpty ? '.jpg' : ext);

      final inputAbs =
          sourceAbs ?? (await _media.resolve(originalRel)).path;
      final thumbAbs = (await _media.resolve(thumbRel)).path;
      final mediumAbs = (await _media.resolve(mediumRel)).path;

      final derived = await ThumbnailPipeline().generate(
        sourceAbs: inputAbs,
        thumbAbs: thumbAbs,
        mediumAbs: mediumAbs,
        thumbRel: thumbRel,
        mediumRel: mediumRel,
      );
      await dao.updateDerived(
        assetId,
        thumbPath: derived.thumbRel,
        mediumPath: derived.mediumRel,
        width: writeSourceMeta ? derived.width : null,
        height: writeSourceMeta ? derived.height : null,
        sizeBytes: writeSourceMeta ? derived.sizeBytes : null,
        hashSha256: writeSourceMeta ? derived.hashSha256 : null,
      );
    } on Object {
      // 降级：保留原图，等待 backfillDerived 重跑。
      // 这里必须连 Error 一起兜——损坏图片的解码器抛的是 RangeError，
      // 只 catch Exception 会让"挂一张坏图"直接把流程打断。
    }
  }

  /// 音频派生（W20 P1-9）：时长写进 `durationMs`，内嵌封面走缩略图管线
  ///
  /// 两者互相独立：没有封面的音频照样有正确的时长，反之亦然。
  Future<void> _deriveAudio(
    AssetsDao dao,
    int assetId,
    String originalRel,
  ) async {
    // 1) 时长 + 封面（读不出就都是 null，不抛）
    final info = await const AudioMetadataProbe()
        .probe((await _media.resolve(originalRel)).path);
    final ms = info.durationMs;
    if (ms != null && ms > 0) {
      await dao.updateDuration(assetId, durationMs: ms);
    }

    // 2) 封面 → 两级缩略图。封面来自 ID3/ilst，尺寸可能是 1500×1500，
    //    所以必须先落到临时文件再交给管线，而不是直接当 thumb 存下来。
    final cover = info.coverBytes;
    if (cover == null || cover.isEmpty) return;

    final tmp = File(p.join(
      Directory.systemTemp.path,
      'plainleaf_cover_${assetId}_${p.basename(originalRel)}',
    ));
    try {
      await tmp.writeAsBytes(cover, flush: true);
      await _derive(dao, assetId, originalRel,
          sourceAbs: tmp.path, writeSourceMeta: false);
    } on Object {
      // 封面写不进去/解码失败都只意味着"这张音频没有缩略图"
      // （UI 会照旧显示音频图标），不影响时长已经落库。
    } finally {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } on FileSystemException {
        // 临时文件删不掉交给系统清理，不值得再上一次报错
      }
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
      updatedAt: entry.updatedAt,
      mood: entry.mood,
      notebookId: entry.notebookId,
      notebookName: row.notebook?.name,
      notebookSpace: row.notebook?.space,
      firstAssetRelPath: row.firstAsset?.relPath,
      firstAssetThumbPath: row.firstAsset?.thumbPath,
      // 无附件时保持 null（fromStorage(null) 会退化成 other，那会把"没有附件"
      // 和"附件类型未知"混成同一件事，卡片就会给空记录画一个文件图标）
      firstAttachmentKind: row.firstAttachmentKind == null
          ? null
          : AssetKind.fromStorage(row.firstAttachmentKind),
      attachmentCount: row.attachmentCount,
      contentDelta: entry.contentDelta,
    );
  }

  @override
  Future<TimelineEntry?> findEntryById(int id) async {
    try {
      final entry = await _dao.findById(id);
      if (entry == null) return null;
      return TimelineEntry(
        id: entry.id,
        uuid: entry.uuid,
        title: entry.title,
        plainText: entry.plainText,
        type: EntryType.fromName(entry.type),
        status: EntryStatus.fromName(entry.status),
        pinned: entry.pinned,
        entryDate: entry.entryDate,
        updatedAt: entry.updatedAt,
        mood: entry.mood,
        notebookId: entry.notebookId,
        contentDelta: entry.contentDelta,
      );
    } on Exception catch (error) {
      throw DatabaseException('读取记录详情失败', cause: error);
    }
  }

  @override
  Future<List<EntryAsset>> findAssetsByEntry(int entryId) =>
      _assetsOf(entryId, allKinds: false);

  @override
  Future<List<EntryAsset>> findAllAssetsByEntry(int entryId) =>
      _assetsOf(entryId, allKinds: true);

  /// [findAssetsByEntry] / [findAllAssetsByEntry] 的共用实现。
  /// 两者的差别**只有一条 SQL 条件**，映射逻辑必须共用 ——
  /// 复制一份的下场是新字段只补了其中一处（详情页看得到原名、导出看不到）。
  Future<List<EntryAsset>> _assetsOf(
    int entryId, {
    required bool allKinds,
  }) async {
    final dao = assetsDao;
    if (dao == null) return const <EntryAsset>[];
    try {
      final rows = allKinds
          ? await dao.allByEntry(entryId)
          : await dao.byEntry(entryId);
      return rows.map(_assetToEntity).toList(growable: false);
    } on Exception catch (error) {
      throw DatabaseException('读取附件失败', cause: error);
    }
  }

  EntryAsset _assetToEntity(Asset a) => EntryAsset(
        id: a.id,
        sortIndex: a.sortIndex,
        relPath: a.relPath,
        kind: AssetKind.fromStorage(a.kind),
        thumbPath: a.thumbPath,
        mediumPath: a.mediumPath,
        originalName: a.originalName,
        mimeType: a.mimeType,
        sizeBytes: a.sizeBytes,
        durationMs: a.durationMs,
        width: a.width,
        height: a.height,
      );
}