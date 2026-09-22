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
/// 主题骨架（米白纸张 + 低饱和青绿）见 app/theme.dart；
/// W9 起支持主题模式 / 字体缩放 / 强调色三件套（未引入 flex_color_scheme，理由见 theme.dart）。
/// localizationsDelegates：flutter_quill 工具栏 tooltip 依赖 FlutterQuillLocalizations（W3）。
class PlainLeafApp extends StatelessWidget {
  const PlainLeafApp({super.key, this.routerConfig, this.themeMode});

  /// 可注入路由（测试隔离用）；默认用全局 appRouter
  final GoRouter? routerConfig;

  /// 可注入主题模式（测试隔离用）；为空则跟随 [themeModeProvider]
  final ThemeMode? themeMode;

  @override
  Widget build(BuildContext context) {
    // 主题三件套（W9：主题模式 / 字体缩放 / 强调色）都从 Provider 读，
    // 设置页改一处、整 App 立刻生效；用 Consumer 而不是把 PlainLeafApp 改成
    // ConsumerWidget，是为了保住 const 构造——已有测试里全是 `const PlainLeafApp(...)`。
    return Consumer(
      builder: (context, ref, _) {
        final seed = Color(ref.watch(accentSeedProvider));
        final scale = ref.watch(textScaleProvider);
        return MaterialApp.router(
          title: '素页 PlainLeaf',
          theme: AppTheme.light(seed: seed),
          darkTheme: AppTheme.dark(seed: seed),
          themeMode: themeMode ?? ref.watch(themeModeProvider),
          routerConfig: routerConfig ?? appRouter,
          // 字体缩放走 MediaQuery 覆盖：textScaleFactor 已废弃，改用 TextScaler
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox.shrink(),
          ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
        );
      },
    );
  }
}