import 'package:flutter/material.dart';

/// 统一空态组件（W8）
///
/// 设计约束（DEVELOPMENT.md 第 123 行：空态/加载态/错误态缺一不可）：
/// - 不写死任何颜色，一律取 Theme 的 colorScheme / textTheme，浅色与深色模式自适应；
/// - 主体居中、留白充足，图标与文案层次分明，不做成弹窗；
/// - 主行动用 FilledButton.tonal，次级用 TextButton；没有回调就不渲染按钮，
///   不留 disabled 占位，避免误导用户存在不可用的操作；
/// - 加 Semantics 容器，方便用 find.text / find.byType 做无障碍与测试定位。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  /// 主视觉图标（如 Icons.search_outlined）
  final IconData icon;

  /// 主文案（一句话说明「为什么这里什么都没有」）
  final String title;

  /// 说明文案（可选，进一步引导后续动作）
  final String? subtitle;

  /// 主行动按钮文案（与 [onAction] 配套；缺回调则不渲染）
  final String? actionLabel;

  /// 主行动按钮回调（与 [actionLabel] 配套）
  final VoidCallback? onAction;

  /// 次级行动按钮文案（与 [onSecondaryAction] 配套；缺回调则不渲染）
  final String? secondaryActionLabel;

  /// 次级行动按钮回调（与 [secondaryActionLabel] 配套）
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    // 全部取主题色板与字体，禁止写死颜色，保证深浅色模式可用。
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasPrimary = actionLabel != null && onAction != null;
    final hasSecondary = secondaryActionLabel != null && onSecondaryAction != null;

    // 图标用主色但降低不透明度，既醒目又不刺眼（仍是主题色，非写死颜色）。
    final mutedPrimary = colorScheme.primary.withAlpha(140);

    return Semantics(
      container: true,
      label: title,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: mutedPrimary),
              const SizedBox(height: 16),
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (hasPrimary) ...[
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
              if (hasSecondary) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSecondaryAction,
                  child: Text(secondaryActionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
