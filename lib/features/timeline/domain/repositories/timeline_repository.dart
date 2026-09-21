import '../entities/timeline_entry.dart';
import '../entities/timeline_filter.dart';

/// 记录仓库接口（features/timeline/domain）。
/// 实现见 data/timeline_repository_impl.dart；UI 只依赖本接口（§4.2 分层红线）。
abstract interface class TimelineRepository {
  /// 时间轴流：未删除、非草稿条目，置顶优先 + 日期倒序，联首图与笔记本。
  /// [filter] 由数据层翻译成 SQL where（W7 组织能力）
  Stream<List<TimelineEntry>> watchTimeline({
    int limit = 100,
    TimelineFilter filter = const TimelineFilter(),
  });

  /// 保存一条新记录：entries + entries_fts 同一事务双写（§4.3 数据红线）
  Future<int> saveEntry(EntryDraft draft);

  /// 更新记录内容：entries 内容列 + entries_fts 同一事务重写；version 递增
  Future<void> updateEntry(int id, EntryDraft draft);

  /// 软删除：deleted 置位 + FTS 行清除，同一事务；物理行保留（回收站预留）
  Future<void> softDelete(int id);

  /// 从回收站恢复：deleted 复位 + FTS 行重建，同一事务
  Future<void> restore(int id);

  /// FTS5 全文检索：返回命中的 entry id（按相关度）
  Future<List<int>> searchIds(String keywords);

  /// 草稿箱流（status=draft，未删除），按更新时间倒序
  Stream<List<TimelineEntry>> watchDrafts();

  /// 回收站流（deleted=true），按更新时间倒序
  Stream<List<TimelineEntry>> watchTrash();

  /// 修改状态（draft ⇄ normal）
  Future<void> setStatus(int id, {required String status});

  /// 置顶开关
  Future<void> setPinned(int id, {required bool pinned});

  /// 回收站 30 天清理：物理删除过期软删行；App 启动调用。返回清理条数
  Future<int> purgeExpiredTrash({int retainDays = 30});

  /// 永久删除（W7）：物理删除条目行 + 清理 FTS/标签/关联资产，不可恢复
  Future<void> hardDelete(int id);

  /// 清空回收站（W7）：永久删除全部软删条目，返回清理条数
  Future<int> emptyTrash();

  /// 为条目挂接一张本地图片（复制进私有目录 + assets 落库），返回 asset id
  Future<int> attachImage(int entryId, String sourcePath);

  /// 条目首图相对路径（时间轴缩略图用；无图返回 null）
  Future<String?> firstImagePath(int entryId);

  /// 补齐历史资产的缩略图（W4 期落库的图没有 thumb），返回处理条数
  Future<int> backfillDerived({int limit = 200});
}