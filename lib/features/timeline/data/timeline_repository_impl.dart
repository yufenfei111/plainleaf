import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/daos/entries_dao.dart';
import '../../../core/db/database.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/entities/timeline_entry.dart';
import '../domain/repositories/timeline_repository.dart';

/// [TimelineRepository] 的本地 Drift 实现。
/// 一致性：所有写操作走 DAO 事务原语（含 FTS 双写）；DAO 异常在调用点统一
/// 包装为 [DatabaseException]（错误三层透传第一层）。
class LocalTimelineRepository implements TimelineRepository {
  const LocalTimelineRepository(this._dao);

  final EntriesDao _dao;

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
    );
  }
}