import 'dart:async';

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
  _tuneImageCache();

  final db = PlainLeafDatabase();
  await DemoSeed.maybeSeed(db);
  // 回收站 30 天清理（§4.3）：W10 起不再阻塞首帧。
  // 它只是「删掉 30 天前就该没了的软删行」，晚几百毫秒执行没有任何可见影响，
  // 却实打实地把启动时间按在启动路径上——冷启动每多一次事务就多一次 IO 等待。
  unawaited(_purgeExpiredTrash(db));

  runApp(
    ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const PlainLeafApp(),
    ),
  );
}

/// 回收站过期清理（失败静默；清理失败不得丢用户数据）
Future<void> _purgeExpiredTrash(PlainLeafDatabase db) async {
  try {
    await db.entriesDao.purgeExpiredTrash();
  } on Exception {
    // 首启/只读场景忽略
  }
}

/// 解码缓存容量调优（W10 首屏/滑动性能）
///
/// 默认 ImageCache 上限是 1000 张 / 100MB。列表与相册滑动时，缩略图会被
/// 大批淘汰再重新解码——滑回去时每张都要重跑一次解码，是「来回滑动掉帧」的
/// 直接原因。按实际使用（thumb 长边 400 ≈ 0.6MB/张）收紧张数、放宽字节，
/// 让缓存真正服务于「最近看过的两屏」而不是一堆永不复用的大图。
void _tuneImageCache() {
  final cache = PaintingBinding.instance.imageCache;
  cache
    ..maximumSize = 400
    ..maximumSizeBytes = 96 << 20; // 96 MB
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