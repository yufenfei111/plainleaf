import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../timeline/domain/entities/entry_asset.dart';
import '../../../timeline/domain/entities/timeline_entry.dart';
import '../../../timeline/presentation/providers/timeline_providers.dart';

/// 单条记录详情（W8）
///
/// 页面只拿一个 id，具体的「去哪张表、怎么映射成领域实体」全部封在仓库里
/// （§4.2 分层红线：页面不碰 DAO / 文件系统）。family 把 id 编进 Provider key，
/// 不同记录的详情互不串缓存，也便于路由按 id 复用。
final entryDetailProvider =
    FutureProvider.family<TimelineEntry?, int>((ref, id) async {
  return ref.watch(timelineRepositoryProvider).findEntryById(id);
});

/// 记录下的全部图片资产（W8 图片浏览用），按 sortIndex 升序。
///
/// 与 [entryDetailProvider] 同源（都走 timelineRepositoryProvider），
/// assetsDao 未注入时仓库层返回空列表而非抛错，页面据此不显示图片区。
final entryAssetsProvider =
    FutureProvider.family<List<EntryAsset>, int>((ref, entryId) async {
  return ref.watch(timelineRepositoryProvider).findAssetsByEntry(entryId);
});
