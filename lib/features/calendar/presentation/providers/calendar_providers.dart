import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/db/daos/entries_dao.dart';
import '../../../timeline/presentation/providers/timeline_providers.dart';
import '../../domain/calendar_month.dart';
import '../../domain/entities/calendar_entry.dart';

/// 当前选中的月份（一律归一化为当月 1 号）。
///
/// 为什么 StateProvider 里存归一化后的值：月份比较用 `==` 最省事，
/// 带上原始时分秒的话「2026-09-01 08:00」与「2026-09-01 00:00」会被判成两个月，
/// 切换按钮就会莫名失灵。
final selectedMonthProvider =
    StateProvider<DateTime>((ref) => monthStart(DateTime.now()));

/// 选中月份的「哪天有几条」轻量命中（只有 id 与日期，不带正文）。
///
/// 直接消费 DAO 的流而不是过一层仓库：这条流本就是把 `watchEntryDates` 的
/// Drift 结果原样透出，Riverpod → Data(DAO) 在本项目分层里是被允许的直连；
/// 聚合动作留给纯函数在页面/Dart 层做（见 domain/calendar_month.dart）。
final monthDateHitsProvider = StreamProvider<List<EntryDateHit>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref
      .watch(dbProvider)
      .entriesDao
      .watchEntryDates(monthStart(month), nextMonthStart(month));
});

/// 某一天的全部记录（点日历格子后的底部弹层消费）。
///
/// 为什么用 family 而不是把「选中那天」也塞进全局 StateProvider：
/// 弹层开关是局部一次性的交互，弹层关掉后这个流应当随订阅一起释放；
/// 放进全局状态反而要自己管清理，还会在同一天反复打开时残留上一份结果。
///
/// 先由 DAO 拿到当天的 id 集合（轻量），再逐条取详情：一个自然日的记录通常个位数，
/// 这点串行查询远小于为一个日历弹层去扩 DAO 接口的成本。
final dayEntriesProvider =
    StreamProvider.family<List<CalendarEntry>, DateTime>((ref, day) {
  final from = dayKey(day);
  final to = DateTime(from.year, from.month, from.day + 1);
  final dao = ref.watch(dbProvider).entriesDao;
  final repo = ref.watch(timelineRepositoryProvider);
  return dao.watchEntryDates(from, to).asyncMap((hits) async {
    final loaded = await Future.wait(
      hits.map((hit) => repo.findEntryById(hit.id)),
    );
    return [
      for (final entry in loaded)
        if (entry != null)
          CalendarEntry(
            id: entry.id,
            date: entry.entryDate,
            title: entry.title,
            snippet: entry.plainText,
            thumbRelPath: entry.firstAssetThumbPath ?? entry.firstAssetRelPath,
          ),
    ];
  });
});
