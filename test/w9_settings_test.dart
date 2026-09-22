import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/app/theme.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/settings/presentation/settings_page.dart';
import 'package:plainleaf/main.dart';

/// 用同一个内存库重建 App（外层必须是 PlainLeafApp，挂着 quill 的本地化 delegate）。
/// themeMode 固定为浅色，避免测试受设备深色设置干扰。
Widget _buildApp(PlainLeafDatabase db) => ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: PlainLeafApp(
        themeMode: ThemeMode.light,
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, state) => const SettingsPage()),
          ],
        ),
      ),
    );

/// 取离 SettingsPage 最近的 ProviderContainer，便于在测试里读 Provider 状态。
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));

void main() {
  testWidgets('① 默认渲染出主题模式/字体缩放/强调色三项', (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    await tester.pumpWidget(_buildApp(db));
    await tester.pumpAndSettle();

    // 三项分组标题都渲染出来了
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('字体缩放'), findsOneWidget);
    expect(find.text('强调色'), findsOneWidget);

    // 默认偏好与冻结接口一致
    final c = _container(tester);
    expect(c.read(themeModeProvider), ThemeMode.system);
    expect(c.read(textScaleProvider), 1.0);
    expect(c.read(accentSeedProvider), AppTheme.primary.toARGB32());

    await db.close();
  });

  testWidgets('② 点击「深色」后 themeModeProvider 变为 ThemeMode.dark',
      (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    await tester.pumpWidget(_buildApp(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(_container(tester).read(themeModeProvider), ThemeMode.dark);
    await db.close();
  });

  testWidgets('③ 切换字体档位后状态变化且值来自 options', (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    await tester.pumpWidget(_buildApp(db));
    await tester.pumpAndSettle();

    // 「较大」对应 TextScaleController.options 里的 1.15
    await tester.tap(find.text('较大'));
    await tester.pumpAndSettle();

    final scale = _container(tester).read(textScaleProvider);
    expect(scale, 1.15);
    expect(TextScaleController.options, contains(scale));
    await db.close();
  });

  testWidgets('④ 切换强调色后状态等于该预设色的 ARGB32', (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    await tester.pumpWidget(_buildApp(db));
    await tester.pumpAndSettle();

    // 选中第二个预设「黛蓝」
    await tester.tap(find.byKey(const Key('accent-黛蓝')));
    await tester.pumpAndSettle();

    expect(
      _container(tester).read(accentSeedProvider),
      AppTheme.accents[1].color.toARGB32(),
    );
    await db.close();
  });

  testWidgets('⑤ 持久化：改偏好后重建容器仍能读回（验证主代理的存储实现）',
      (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());

    // 第一次启动：写入主题模式 = 深色
    await tester.pumpWidget(_buildApp(db));
    await tester.pumpAndSettle();
    await _container(tester).read(themeModeProvider.notifier).set(ThemeMode.dark);
    await tester.pumpAndSettle();

    // 销毁旧容器，用同一个内存库「重启」App，模拟进程重启后从 settings_kv 读回
    await tester.pumpWidget(_buildApp(db));
    await tester.pumpAndSettle();

    // 关键断言：若读不回来（仍是 system）说明 settings_kv 持久化有 bug
    expect(_container(tester).read(themeModeProvider), ThemeMode.dark);
    await db.close();
  });

  testWidgets('原有导出/恢复入口未被改坏', (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    await tester.pumpWidget(_buildApp(db));
    await tester.pumpAndSettle();

    // 备份/导出分组在外观卡片下方，小视口下低处条目可能离屏（offstage），
    // find 默认跳过离屏控件；用 skipOffstage:false 确认入口确实还在。
    expect(find.text('导出备份包（.plbk）', skipOffstage: false), findsWidgets);
    expect(find.text('从备份包恢复（.plbk）', skipOffstage: false), findsWidgets);
    expect(
      find.byIcon(Icons.notes_outlined, skipOffstage: false),
      findsWidgets,
    );
    await db.close();
  });
}
