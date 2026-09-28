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

/// 记录下的**全部**附件（W19 详情页附件区），按 sortIndex 升序。
///
/// 与 [entryAssetsProvider] 的分工不能混：那个是"能翻看的图片"（横向翻页只该拿图片，
/// 混进 PDF 就会出现翻到一张打不开的页），这个是"这条记录带了哪些文件"。
/// 两者都保留而不是合成一个带过滤参数的 Provider —— 语义不同，
/// 合成后每个调用点都要重新回答一次"我要的是哪种"，出错只是时间问题。
final entryAttachmentsProvider =
    FutureProvider.family<List<EntryAsset>, int>((ref, entryId) async {
  return ref.watch(timelineRepositoryProvider).findAllAssetsByEntry(entryId);
});
