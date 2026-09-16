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
  Future<void> softDelete(int id) async {
    try {
      await _dao.softDelete(id);
    } on Exception catch (error) {
      throw DatabaseException('删除记录失败', cause: error);
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

  TimelineEntry _rowToEntity(TimelineRow row) {
    final entry = row.entry;
    return TimelineEntry(
      id: entry.id,
      uuid: entry.uuid,
      title: entry.title,
      plainText: entry.plainText,
      type: EntryType.fromName(entry.type),
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