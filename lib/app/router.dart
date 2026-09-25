import 'package:go_router/go_router.dart';

import '../features/calendar/presentation/pages/calendar_page.dart';
import '../features/detail/presentation/entry_detail_page.dart';
import '../features/editor/presentation/drafts_page.dart';
import '../features/editor/presentation/editor_page.dart';
import '../features/importer/presentation/markdown_import_page.dart';
import '../features/editor/presentation/trash_page.dart';
import '../features/search/presentation/search_page.dart';
import '../features/gallery/presentation/gallery_page.dart';
import '../features/notebooks/presentation/notebooks_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/study/presentation/study_page.dart';
import '../features/timeline/presentation/timeline_page.dart';
import 'home_page.dart';
import 'transitions.dart';

/// 底部 4 Tab 信息架构（W12 调整）：
/// ① 时间轴（首页）② 相册 ③ 学习 ④ 我的
/// 原「笔记本」不再是 Tab（见下方顶层 /notebooks 路由）。
/// StatefulShellRoute.indexedStack：各 Tab 独立导航栈，切换不丢状态。
/// 硬约束：branches 数量必须与 HomePage 的 NavigationBar destinations 数量相等。
///
/// 全局路由（W3）：
/// - /editor        新建记录（先落草稿拿 id，500ms 防抖自动保存）
/// - /editor?id=N   编辑已有记录
/// - /drafts        草稿箱
/// - /trash         回收站
/// - /detail?id=N   记录详情页（W8：medium 大图 + 富文本只读浏览）
/// - /calendar      日历回顾（W12：按天回看，入口在时间轴工具栏）
/// 编辑器与详情页路由放在 shell 之外：全屏沉浸，不显示底部 Tab。
///
/// W12 信息架构调整：底部 Tab 由 5 个减为 4 个（时间轴/相册/学习/我的），
/// 原「笔记本」不再是并列一级目的地 —— 它是记录的一个维度，入口收进「我的」。
/// /notebooks 因此从 shell 的 branch 提升为普通顶层路由，仍可 push 进入。
GoRouter buildAppRouter() => GoRouter(
  initialLocation: '/timeline',
  routes: [
    GoRoute(
      path: '/editor',
      pageBuilder: (context, state) => fadeSlidePage(
        state,
        EditorPage(
            entryId: int.tryParse('${state.uri.queryParameters['id']}')),
      ),
    ),
    GoRoute(
      path: '/drafts',
      pageBuilder: (context, state) =>
          fadeSlidePage(state, const DraftsPage()),
    ),
    GoRoute(
      path: '/import',
      pageBuilder: (context, state) =>
          fadeSlidePage(state, const MarkdownImportPage()),
    ),
    GoRoute(
      path: '/search',
      pageBuilder: (context, state) =>
          fadeSlidePage(state, const SearchPage()),
    ),
    GoRoute(
      path: '/detail',
      pageBuilder: (context, state) {
        // 缺 id 或非法 id 时传 -1：详情页查不到记录会走「不存在」空态，
        // 而不是在此处抛异常把整个路由树搞崩。
        final id = int.tryParse(state.uri.queryParameters['id'] ?? '');
        return fadeSlidePage(state, EntryDetailPage(entryId: id ?? -1));
      },
    ),
    GoRoute(
      path: '/trash',
      pageBuilder: (context, state) => fadeSlidePage(state, const TrashPage()),
    ),
    // 笔记本（W12）：从底部 Tab 降级为「我的」Tab 内的入口，走与 /search、/trash
    // 一致的顶层全屏路由——不再占用 StatefulShellRoute 的一个 branch。
    GoRoute(
      path: '/notebooks',
      pageBuilder: (context, state) =>
          fadeSlidePage(state, const NotebooksPage()),
    ),
    GoRoute(
      path: '/calendar',
      pageBuilder: (context, state) =>
          fadeSlidePage(state, const CalendarPage()),
    ),
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
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        ]),
      ],
    ),
  ],
);
/// 应用全局路由实例（测试中请用 [buildAppRouter] 构建隔离实例）
final appRouter = buildAppRouter();
