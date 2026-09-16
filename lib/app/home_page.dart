import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 壳组件：底部 NavigationBar 切换 5 个 Tab
/// Tab 命名与顺序来源：计划书 §5.1（时间轴/相册/学习/笔记本/我的）
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.shell});

  final StatefulNavigationShell shell;

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
      icon: Icon(Icons.book_outlined),
      selectedIcon: Icon(Icons.book),
      label: '笔记本',
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: _destinations,
      ),
    );
  }
}