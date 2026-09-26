import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/core/security/app_lock.dart';
import 'package:plainleaf/core/security/crypto_service.dart';
import 'package:plainleaf/core/security/secret_store.dart';
import 'package:plainleaf/features/settings/presentation/app_lock_gate.dart';
import 'package:plainleaf/features/settings/presentation/lock_screen.dart';
import 'package:plainleaf/features/settings/presentation/providers/security_providers.dart';

/// 应用锁 UI（W14）
///
/// 测试里一律 override 掉 [secretStoreProvider]：flutter_secure_storage 走平台通道，
/// `flutter test` 里调用必抛 MissingPluginException，不能让它混进 UI 用例。
CryptoService fastCrypto() => CryptoService(
      kdf: Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 1000, bits: 256),
    );

/// 推到异步 Future 落地。刻意不用 pumpAndSettle：校验期间有一个转圈控件，
/// 常驻动画会让 pumpAndSettle 永远等不到"静止"。
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('① 锁屏：密码错留在原地报错，密码对才放行', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(MaterialApp(
      home: AppLockScreen(
        verify: (password) async => password == '1234',
        onUnlocked: () => unlocked = true,
      ),
    ));

    await tester.enterText(
        find.byKey(const Key('lock-password-field')), '9999');
    await tester.tap(find.byKey(const Key('lock-submit')));
    await settle(tester);

    expect(find.byKey(const Key('lock-error')), findsOneWidget);
    expect(unlocked, isFalse);

    // 失败后输入框被清空，用户可以直接重输，不必手动全选
    await tester.enterText(
        find.byKey(const Key('lock-password-field')), '1234');
    await tester.tap(find.byKey(const Key('lock-submit')));
    await settle(tester);

    expect(unlocked, isTrue);
  });

  testWidgets('② 门控：应用锁开启时先挡一层，解锁后才是内容', (tester) async {
    // 两侧必须是**同一个** KDF 参数：迭代次数参与密钥派生，
    // 设密码用 1000 次、校验用默认 10 万次会派生出两把不同的密钥
    // （这个坑的代价就是"密码正确却死活解不开"）。
    final crypto = fastCrypto();
    final store = InMemorySecretStore();
    await AppLockService(store, crypto: crypto).setPassword('1234');

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        secretStoreProvider.overrideWithValue(store),
        cryptoServiceProvider.overrideWithValue(crypto),
        // FutureProvider 在 Riverpod 2.x 没有 overrideWithValue，用 overrideWith
        appLockEnabledProvider.overrideWith((ref) async => true),
      ],
      child: const MaterialApp(
        home: AppLockGate(child: Text('真正的首页内容')),
      ),
    ));
    await settle(tester);

    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(find.text('真正的首页内容'), findsNothing);

    await tester.enterText(
        find.byKey(const Key('lock-password-field')), '1234');
    await tester.tap(find.byKey(const Key('lock-submit')));
    await settle(tester);

    expect(find.text('真正的首页内容'), findsOneWidget);
  });

  testWidgets('③ 门控：没开应用锁时不该出现任何拦门，也不能拖延首屏', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: AppLockGate(child: Text('正文')),
      ),
    ));
    // 刻意不多给 pump：FutureProvider 还没回来时也必须直接放内容，
    // 否则"每帧都要等一次异步读状态"会把首屏拖出肉眼可见的延迟。
    await tester.pump();

    expect(find.text('正文'), findsOneWidget);
    expect(find.byType(AppLockScreen), findsNothing);
  });
}
