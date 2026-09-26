import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 壳组件：底部 NavigationBar 切换 4 个 Tab
///
/// 命名与顺序：时间轴 / 相册 / 学习 / 我的。
/// 硬约束：这里 destinations 的数量必须与 `StatefulShellRoute` 的 branches 数量
/// 严格相等——多一个或少一个都会在运行时直接抛错，两处必须联动改。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// 「我的」在 destinations/branches 中的下标（对应 /settings 分支）
  static const _mineIndex = 3;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.timeline_outlined),
      selectedIcon: Icon(Icons.timeline),
      label: '时间轴',
    ),
    NavigationDestination(
      icon: Icon(Icons.photo_outlined),
      selectedIcon: Icon(Icons.photo),
      label: '相册',
    ),
    NavigationDestination(
      icon: Icon(Icons.school_outlined),
      selectedIcon: Icon(Icons.school),
      label: '学习',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      // 笔记本入口（W12）：原「笔记本」Tab 取消后，入口收进「我的」Tab。
      // 为什么用 FAB 而不是往设置页里插一行：不能改 settings_page.dart（不在本次改动
      // 范围内），而 FAB 是 Material 中最标准的「本页附加动作」，不占列表排版、
      // 也不会把设置页内容顶下去。仅在「我的」Tab 上浮出，避免与时间轴自己的
      // 「记一笔」FAB 叠在一起。
      floatingActionButton: shell.currentIndex == _mineIndex
          ? FloatingActionButton.extended(
              // Hero tag 必须显式给且唯一：IndexedStack 下各 Tab 的 Scaffold 同时
              // 存在于树里，两个 FAB 都用默认 tag 会撞「multiple heroes share the
              // same tag」，切到「我的」就抛断言。
              heroTag: 'home-notebooks-entry',
              onPressed: () => context.push('/notebooks'),
              icon: const Icon(Icons.book_outlined),
              label: const Text('笔记本'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: _destinations,
      ),
    );
  }
}
