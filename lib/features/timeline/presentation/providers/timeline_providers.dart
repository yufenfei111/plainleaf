import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../data/timeline_repository_impl.dart';
import '../../domain/entities/timeline_entry.dart';
import '../../domain/entities/timeline_filter.dart';
import '../../domain/repositories/timeline_repository.dart';

/// 时间轴仓库（UI 不直接触碰 DAO——一律经由本 Provider 注入的接口实现）
final timelineRepositoryProvider = Provider<TimelineRepository>((ref) {
  return LocalTimelineRepository(
    ref.watch(dbProvider).entriesDao,
    assetsDao: ref.watch(dbProvider).assetsDao,
    mediaStorage: ref.watch(mediaStorageProvider),
  );
});

/// 时间轴筛选条件（W7）：UI 改这个 → 流自动重查（SQL where 下推，非客户端过滤）
final timelineFilterProvider =
    StateProvider<TimelineFilter>((ref) => const TimelineFilter());

/// 时间轴数据流（AsyncValue 三层透传：loading / data / error 由页面 .when 消费）
final timelineStreamProvider = StreamProvider<List<TimelineEntry>>((ref) {
  final filter = ref.watch(timelineFilterProvider);
  return ref.watch(timelineRepositoryProvider).watchTimeline(filter: filter);
});

/// 草稿箱流（W3）
final draftsStreamProvider = StreamProvider<List<TimelineEntry>>((ref) {
  return ref.watch(timelineRepositoryProvider).watchDrafts();
});

/// 回收站流（W3）
final trashStreamProvider = StreamProvider<List<TimelineEntry>>((ref) {
  return ref.watch(timelineRepositoryProvider).watchTrash();
});

/// 写操作门面（W7）
///
/// 页面只做两件事：调用这里的方法、把异常转成 SnackBar。
/// 这样"置顶/删除/恢复/清空"在多个页面复用同一套错误处理，
/// 不必每个 Widget 里各写一遍 try/catch（错误三层透传的第二、三层之间）。
final timelineActionsProvider = Provider<TimelineActions>((ref) {
  return TimelineActions(ref.watch(timelineRepositoryProvider));
});

class TimelineActions {
  const TimelineActions(this._repo);

  final TimelineRepository _repo;

  /// 置顶开关：返回切换后的状态，供 UI 出提示文案
  Future<bool> togglePinned(TimelineEntry entry) async {
    final next = !entry.pinned;
    await _repo.setPinned(entry.id, pinned: next);
    return next;
  }

  Future<void> softDelete(int id) => _repo.softDelete(id);

  Future<void> restore(int id) => _repo.restore(id);

  Future<void> hardDelete(int id) => _repo.hardDelete(id);

  Future<int> emptyTrash() => _repo.emptyTrash();

  /// 补齐历史缩略图（W6 遗留入口；返回处理条数）
  Future<int> backfillDerived({int limit = 200}) =>
      _repo.backfillDerived(limit: limit);
}
