import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 统一的页面过渡（W10 交互打磨）
///
/// 此前所有路由都走平台默认过渡（Android 是整页上下推），进入编辑器/详情页时
/// 显得生硬且跟内容没有连续性。这里统一成 200ms 淡入 + 极小幅度上移：
/// - 淡入比平移更「轻」，不会让用户感觉等待；
/// - 位移只给 1.5% 视高，足以暗示「新页从下方来」，又不拖慢感知速度；
/// - 退出比进入略快（160ms），返回手感更利落。
///
/// 底部 Tab 的 5 个常驻页**不套用**（Shell 内切换用 indexedStack，本来就不重建）。
CustomTransitionPage<void> fadeSlidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
