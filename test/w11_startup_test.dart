import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/app/theme.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/db/settings_store.dart';
import 'package:plainleaf/main.dart';

/// W10 收尾 · 首屏主题预读
///
/// 目标不是覆盖率，而是守住一条用户可感知的红线：启动那一下不能「默认主题 →
/// 恢复主题」闪一帧；同时预读失败绝不能拖累启动。
/// 优先用 ProviderContainer 直接测 provider（不受 FakeAsync/渲染干扰），
/// 只留一条 Widget 用例验证「首帧 MaterialApp 就是终值」。
void main() {
  late PlainLeafDatabase db;

  setUp(() async {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
  });

  tearDown(() async {
    try {
      await db.close();
    } on Object {
      // 容忍二次关闭
    }
  });

  /// 等异步恢复落地（纯 Dart 用例，真实定时器可用）
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 100));

  test('① 预读：库里有偏好时三件套一次读全', () async {
    final store = SettingsStore(db);
    await store.writeString(SettingKeys.themeMode, ThemeMode.dark.name);
    await store.writeString(SettingKeys.textScale, '1.15');
    await store.writeString(
      SettingKeys.accentSeed,
      '${AppTheme.accents[1].color.toARGB32()}',
    );

    final snapshot = await readAppearanceSnapshot(db);

    expect(snapshot.themeMode, ThemeMode.dark);
    expect(snapshot.textScale, 1.15);
    expect(snapshot.accentSeed, AppTheme.accents[1].color.toARGB32());
  });

  test('② 预读：库里没有偏好时三个字段都是 null（不是默认值）', () async {
    final snapshot = await readAppearanceSnapshot(db);

    // null 才对：表示「交给 Controller 自己的默认值」，默认值只在一处定义
    expect(snapshot.themeMode, isNull);
    expect(snapshot.textScale, isNull);
    expect(snapshot.accentSeed, isNull);
  });

  test('③ 预读：脏值被丢弃，不污染首帧', () async {
    final store = SettingsStore(db);
    await store.writeString(SettingKeys.themeMode, 'not_a_mode');
    await store.writeString(SettingKeys.textScale, '99');

    final snapshot = await readAppearanceSnapshot(db);

    expect(snapshot.themeMode, isNull);
    expect(snapshot.textScale, isNull, reason: '档位外的倍率必须丢弃');
  });

  test('④ 注入快照：themeModeProvider 首帧即 dark，不必等异步恢复', () async {
    final container = ProviderContainer(overrides: [
      dbProvider.overrideWithValue(db),
      initialAppearanceProvider.overrideWithValue(
        const AppearanceSnapshot(themeMode: ThemeMode.dark),
      ),
    ]);
    addTearDown(container.dispose);

    // 关键断言：read 立刻拿到终值（旧实现这里必然先给 system）
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('⑤ 未注入（空快照）：行为与旧版完全一致，异步恢复后仍是 dark', () async {
    await SettingsStore(db).writeString(SettingKeys.themeMode, ThemeMode.dark.name);

    final container = ProviderContainer(overrides: [
      dbProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    // 同步首值必须还是 system：既有测试/页面的初始假设不能被动到
    expect(container.read(themeModeProvider), ThemeMode.system);

    for (var i = 0;
        i < 20 && container.read(themeModeProvider) == ThemeMode.system;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('⑥ 空快照 + 空库：三件套仍是旧版默认值', () async {
    final container = ProviderContainer(overrides: [
      dbProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(container.read(textScaleProvider), 1.0);
    expect(container.read(accentSeedProvider), AppTheme.primary.toARGB32());

    // 让三个 _restore() 跑完再结束用例（否则关闭库时会有未完成的查询）
    await settle();
  });

  test('⑦ 预读命中后 set() 仍然落库（预读不能顶掉写入路径）', () async {
    final container = ProviderContainer(overrides: [
      dbProvider.overrideWithValue(db),
      initialAppearanceProvider.overrideWithValue(
        const AppearanceSnapshot(themeMode: ThemeMode.dark),
      ),
    ]);
    addTearDown(container.dispose);

    await container.read(themeModeProvider.notifier).set(ThemeMode.light);

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(await SettingsStore(db).readString(SettingKeys.themeMode), 'light');
  });

  testWidgets('⑧ 首帧 MaterialApp 就是注入的 dark，后续帧不再跳回', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          initialAppearanceProvider.overrideWithValue(
            const AppearanceSnapshot(
              themeMode: ThemeMode.dark,
              textScale: 1.15,
              accentSeed: 0xFF4E9B8F,
            ),
          ),
        ],
        child: PlainLeafApp(routerConfig: router),
      ),
    );

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
      reason: '首帧就要是终值，不能有「system → dark」的那一帧重绘',
    );

    // 只 pump 一帧，不用 pumpAndSettle：路由/流迟迟不就绪时 settle 会拖到超时
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
      reason: '异步恢复跑完后不得把预读值覆盖回去',
    );
  });
}
