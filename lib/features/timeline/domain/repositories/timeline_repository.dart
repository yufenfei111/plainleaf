import '../entities/timeline_entry.dart';

/// 时间轴仓库接口（features/timeline/domain）。
/// 实现见 data/timeline_repository_impl.dart；UI 只依赖本接口（§4.2 分层红线）。
abstract interface class TimelineRepository {
  /// 时间轴流：未删除条目，置顶优先 + 日期倒序，联首图与笔记本
  Stream<List<TimelineEntry>> watchTimeline({int limit = 100});

  /// 保存一条新记录：entries + entries_fts 同一事务双写（§4.3 数据红线）
  Future<int> saveEntry(EntryDraft draft);

  /// 软删除：deleted 置位 + FTS 行清除，同一事务；物理行保留（回收站预留）
  Future<void> softDelete(int id);

  /// FTS5 全文检索：返回命中的 entry id（按相关度）
  Future<List<int>> searchIds(String keywords);
}