import 'package:flutter/material.dart';

/// 轻量骨架屏（W10 收尾）
///
/// 为什么用骨架屏代替转圈：
/// loading 态的信息量不同——转圈只告诉用户「在忙」，骨架屏顺带把
/// 「接下来会是什么样」提前画出来，密集列表场景的感知等待明显更短。
///
/// 为什么**不做呼吸/微光动画**：
/// 1. 设计红线是「动画克制」——列表每次刷新都闪一遍属于自我炫耀；
/// 2. 循环动画会让 `flutter test` 的 `pumpAndSettle` 永远等不到静止，
///    直接把整个 Widget 测试挂死。为了省几百毫秒的观感牺牲可测性不划算。
///
/// 用法与 [EmptyState] 对称：颜色一律取 Theme，深浅色模式自适应；
/// 外层加 Semantics，便于 find.byType / 无障碍朗读识别。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 6,
  });

  /// 宽度；为 null 时撑满父容器（配合 Row/Column 的 Expanded）
  final double? width;

  /// 高度
  final double height;

  /// 圆角
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// 时间轴/列表类 loading 占位：若干张「卡片骨架」，形状对齐真实卡片
/// （52dp 缩略图 + 标题行 + 两行正文 + 两个小 chip）。
///
/// 刻意只画 6 条：真实列表首屏也就这个量级，多画等于用无意义像素换布局开销。
class TimelineSkeleton extends StatelessWidget {
  const TimelineSkeleton({super.key, this.itemCount = 6});

  /// 占位卡片数量
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '加载中',
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        itemCount: itemCount,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                    width: 52,
                    height: 52,
                    radius: 12,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: (i % 2 == 0) ? 180 : 120, height: 16),
                        const SizedBox(height: 8),
                        SkeletonBox(width: double.infinity, height: 12),
                        const SizedBox(height: 6),
                        SkeletonBox(width: 220, height: 12),
                        const SizedBox(height: 10),
                        Row(
                          children: const [
                            SkeletonBox(width: 44, height: 18, radius: 6),
                            SizedBox(width: 6),
                            SkeletonBox(width: 62, height: 18, radius: 6),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 相册/网格类 loading 占位：按 3 列铺 [count] 个方块。
class GridSkeleton extends StatelessWidget {
  const GridSkeleton({super.key, this.count = 9, this.crossAxisCount = 3});

  /// 占位格子数量
  final int count;

  /// 每行列数（与真实网格保持一致）
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '加载中',
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: count,
        itemBuilder: (context, i) =>
            const SkeletonBox(width: double.infinity, height: double.infinity, radius: 12),
      ),
    );
  }
}
