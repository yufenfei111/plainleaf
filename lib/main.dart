import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/db/database.dart';
import 'core/db/seed.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = PlainLeafDatabase();
  await DemoSeed.maybeSeed(db);
  // 回收站 30 天清理（§4.3）：启动时静默执行，失败不阻塞启动
  try {
    await db.entriesDao.purgeExpiredTrash();
  } on Exception {
    // 首启/只读场景静默忽略；清理失败不得丢用户数据
  }

  runApp(
    ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const PlainLeafApp(),
    ),
  );
}

/// 素页 PlainLeaf 根组件
/// 主题骨架（米白纸张 + 低饱和青绿）见 app/theme.dart；W9 接 flex_color_scheme。
/// localizationsDelegates：flutter_quill 工具栏 tooltip 依赖 FlutterQuillLocalizations（W3）。
class PlainLeafApp extends StatelessWidget {
  const PlainLeafApp({super.key, this.routerConfig});

  /// 可注入路由（测试隔离用）；默认用全局 appRouter
  final GoRouter? routerConfig;

  /// 可注入路由（测试隔离用）；默认用全局 appRouter

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '素页 PlainLeaf',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: routerConfig ?? appRouter,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
    );
  }
}