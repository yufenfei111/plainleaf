import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/db/database.dart';
import 'core/db/seed.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = PlainLeafDatabase();
  await DemoSeed.maybeSeed(db);

  runApp(
    ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const PlainLeafApp(),
    ),
  );
}

/// 素页 PlainLeaf 根组件
/// 主题骨架（米白纸张 + 低饱和青绿）见 app/theme.dart；W9 接 flex_color_scheme。
class PlainLeafApp extends StatelessWidget {
  const PlainLeafApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '素页 PlainLeaf',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}