import 'package:go_router/go_router.dart';

import '../features/gallery/presentation/gallery_page.dart';
import '../features/notebooks/presentation/notebooks_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/study/presentation/study_page.dart';
import '../features/timeline/presentation/timeline_page.dart';
import 'home_page.dart';

/// 底部 5 Tab 信息架构（计划书 §5.1，DEVELOPMENT.md §6 Day 4）：
/// ① 时间轴（首页）② 相册 ③ 学习 ④ 笔记本 ⑤ 我的
/// StatefulShellRoute.indexedStack：各 Tab 独立导航栈，切换不丢状态。
/// 速记箱为全局入口（不占 Tab），W11 排期；编辑器详情页路由 W3 随编辑器接入。
final appRouter = GoRouter(
  initialLocation: '/timeline',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomePage(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/timeline', builder: (_, _) => const TimelinePage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/gallery', builder: (_, _) => const GalleryPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/study', builder: (_, _) => const StudyPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/notebooks', builder: (_, _) => const NotebooksPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        ]),
      ],
    ),
  ],
);