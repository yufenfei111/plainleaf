import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';

/// 「那年今日」一条（展示用最小模型，便于 Widget 测试直接构造）。
///
/// 为什么单独定义而不复用 TimelineEntry：卡片只用到标题、年份差与首图三样，
/// 端上整个领域实体会让卡片测试被迫造一堆无关字段；模型一旦瘦下来，
/// Widget 测试的构造代码就只有三行。
class OnThisDayItem {
  const OnThisDayItem({
    required this.id,
    required this.title,
    required this.yearsAgo,
    this.thumbRelPath,
  });

  /// 记录 id（点卡片进 `/detail?id=`）
  final int id;

  /// 标题；空串由卡片统一显示为「(无标题)」
  final String title;

  /// 「N 年前」里的 N（今天年份 − 记录年份）
  final int yearsAgo;

  /// 首图相对路径（thumb 优先、回退原图）；无图时为 null
  final String? thumbRelPath;
}

/// 「今天」的唯一取值点。
///
/// 单独抽成 Provider 是为了给测试留一个可覆盖的缝：不钉住「今天」的话，
/// 用例会在「2 月 29 日」这类日期上随运行日历漂移（往年根本没有 2/29，
/// 构造出来的日期会被 DateTime 规范化到下个月，断言随之失真）。
final onThisDayTodayProvider = Provider<DateTime>((ref) => DateTime.now());

/// 那年今日数据流（W12）
///
/// 直接消费 DAO 的 `watchOnThisDay`：月日匹配的过滤已在数据层用 Dart 完成
/// （跨 engine 行为一致的取舍），这里只把行映射成展示模型。
///
/// 为什么用 StreamProvider 而不是 FutureProvider：记录随时会被改写或删除，
/// 用户此刻正在看的那条被删掉时，卡片应当自己消失，而不是留着一份过期快照。
final onThisDayProvider = StreamProvider<List<OnThisDayItem>>((ref) {
  final today = ref.watch(onThisDayTodayProvider);
  return ref.watch(dbProvider).entriesDao.watchOnThisDay(today).map(
        (rows) => [
          for (final row in rows)
            OnThisDayItem(
              id: row.entry.id,
              title: row.entry.title,
              yearsAgo: today.year - row.entry.entryDate.year,
              // 有缩略图用缩略图，W4 期历史数据没有 thumb 就回退原图
              thumbRelPath:
                  row.firstAsset?.thumbPath ?? row.firstAsset?.relPath,
            ),
        ],
      );
});
