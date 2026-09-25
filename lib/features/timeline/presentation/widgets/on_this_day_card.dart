import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../../app/providers.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../providers/on_this_day_provider.dart';

/// 时间轴顶部的「那年今日」卡片（W12）
///
/// 三态约定（验收口径：加载 / 空 / 错误态齐全）：
/// - **空**：返回 `const SizedBox.shrink()`——它挂在时间轴列表顶部，若退化成
///   一块空白占位，用户会以为加载卡住了；直接塌成 0 尺寸最干净；
/// - **加载中**：一张与真实卡片同形的静态骨架（不转圈、不呼吸，红线禁止循环动画）；
/// - **错误**：一张紧凑的错误行 + 「重试」入口，绝不留白。
///
/// 为什么「有数据」优先于「加载中」：drift 流每次数据变动都会让 AsyncValue 进入
/// `AsyncLoading(hasValue: true)`，若不加判断就会在每次写记录时闪回骨架。
class OnThisDayCard extends ConsumerWidget {
  const OnThisDayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(onThisDayProvider);
    final items = async.valueOrNull;
    if (items != null) {
      if (items.isEmpty) return const SizedBox.shrink();
      return _buildCard(context, ref, items);
    }
    if (async.hasError) {
      return _ErrorCard(onRetry: () => ref.invalidate(onThisDayProvider));
    }
    return const _LoadingCard();
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref,
    List<OnThisDayItem> items,
  ) {
    final root = ref.watch(supportDirProvider).valueOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
              child: Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '那年今日',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            for (final item in items) _OnThisDayRow(item: item, root: root),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 加载态：与真实卡片同形的静态骨架，形状对得上才不会在数据到达时整块跳变。
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const SkeletonBox(width: 44, height: 44, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 140, height: 14),
                    SizedBox(height: 8),
                    SkeletonBox(width: 80, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 错误态：一句归因 + 原地重试（TextButton 自带 48dp 命中区）。
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('那年今日加载失败')),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片里的一行：缩略图（有则显示）+ 标题 + 「N 年前」标签。
///
/// 整行 60dp 高（44 缩略图 + 上下留白），触控红线 ≥44dp 达标。
class _OnThisDayRow extends StatelessWidget {
  const _OnThisDayRow({required this.item, this.root});

  final OnThisDayItem item;

  /// App 支持目录（相对路径基准）；为 null 时缩略图位用占位，不发起异步
  final String? root;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 先落到局部变量再判空：字段本身无法参与空安全提升，
    // 直接写 `root != null ? p.join(root, ...)` 在静态分析里过不了。
    final baseDir = root;
    final thumbRel = item.thumbRelPath;
    final String? absPath =
        (thumbRel != null && baseDir != null) ? p.join(baseDir, thumbRel) : null;

    return InkWell(
      // 找不到 router 的场合（如纯组件测试）静默跳过，不让导航把整棵树带崩
      onTap: () => GoRouter.maybeOf(context)?.push('/detail?id=${item.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: absPath != null
                    ? Image.file(
                        File(absPath),
                        fit: BoxFit.cover,
                        // 缩略图必须限解码尺寸，否则 44dp 的框里解原图纯属浪费
                        cacheWidth: (44 *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                        errorBuilder: (_, _, _) => Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Container(
                        color: cs.primaryContainer,
                        child: Icon(Icons.auto_stories_outlined, color: cs.primary),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isEmpty ? '(无标题)' : item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.yearsAgo} 年前',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
