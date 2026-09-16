import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../data/timeline_repository_impl.dart';
import '../../domain/entities/timeline_entry.dart';
import '../../domain/repositories/timeline_repository.dart';

/// 时间轴仓库（UI 不直接触碰 DAO——一律经由本 Provider 注入的接口实现）
final timelineRepositoryProvider = Provider<TimelineRepository>((ref) {
  return LocalTimelineRepository(ref.watch(dbProvider).entriesDao);
});

/// 时间轴数据流（AsyncValue 三层透传：loading / data / error 由页面 .when 消费）
final timelineStreamProvider = StreamProvider<List<TimelineEntry>>((ref) {
  return ref.watch(timelineRepositoryProvider).watchTimeline();
});