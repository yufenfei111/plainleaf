import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/core/errors/app_exception.dart';
import 'package:plainleaf/core/security/app_lock.dart';
import 'package:plainleaf/core/security/crypto_service.dart';
import 'package:plainleaf/core/security/secret_store.dart';

/// 测试用低迭代 KDF：生产默认 10 万次，十几个用例跑下来要几十秒，
/// 而本文件要验的是**容器格式与流程**，不是口令强度本身。
CryptoService fastCrypto({Random? random}) => CryptoService(
      kdf: Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 1000, bits: 256),
      random: random ?? Random(42),
    );

void main() {
  group('AES-GCM 加密容器', () {
    test('① 往返：加密后能用同一密码解回原文', () async {
      final crypto = fastCrypto();
      final plain = utf8.encode('素页 PlainLeaf · 加密测试 🎈');
      final blob = await crypto.seal(plain, 'correct horse battery');

      expect(crypto.looksEncrypted(blob), isTrue);
      final clear = await crypto.open(blob, 'correct horse battery');
      expect(utf8.decode(clear), '素页 PlainLeaf · 加密测试 🎈');
    });

    test('② 密码错 → SecurityException(authenticationFailed)', () async {
      final crypto = fastCrypto();
      final blob = await crypto.seal(utf8.encode('秘密'), 'pwd-1234');
      try {
        await crypto.open(blob, 'pwd-5678');
        fail('密码错误却解开了');
      } on SecurityException catch (error) {
        expect(error.kind, SecurityErrorKind.authenticationFailed);
        // 文案必须把"密码错"和"数据被改"说成同一件事——实现上区分不了
        expect(error.userMessage, contains('已被改动'));
      }
    });

    test('③ 密文被改一个字节 → 同样是认证失败（AEAD 的承诺）', () async {
      final crypto = fastCrypto();
      final blob = await crypto.seal(utf8.encode('秘密'), 'pwd-1234');
      final tampered = Uint8List.fromList(blob);
      tampered[tampered.length - 1] ^= 0x01;

      expect(
        () => crypto.open(tampered, 'pwd-1234'),
        throwsA(isA<SecurityException>()),
      );
    });

    test('④ 不是素页容器 → notEncrypted，且不提示去重试密码', () async {
      final crypto = fastCrypto();
      try {
        await crypto.open(utf8.encode('{"app":"plainleaf"}'), 'whatever');
        fail('非加密数据不该被解开');
      } on SecurityException catch (error) {
        expect(error.kind, SecurityErrorKind.notEncrypted);
        expect(error.userMessage, isNot(contains('密码')));
      }
    });

    test('⑤ 同一密码两次加密的密文不同（每次都用新盐）', () async {
      final crypto = fastCrypto();
      final a = await crypto.seal(utf8.encode('同一句话'), 'pwd');
      final b = await crypto.seal(utf8.encode('同一句话'), 'pwd');

      expect(a, isNot(equals(b)));
      // 两次都能解开
      expect(utf8.decode(await crypto.open(a, 'pwd')), '同一句话');
      expect(utf8.decode(await crypto.open(b, 'pwd')), '同一句话');
    });

    test('⑥ 空内容与 64KB 大块都能往返', () async {
      final crypto = fastCrypto();
      final empty = await crypto.seal(<int>[], 'pwd');
      expect(await crypto.open(empty, 'pwd'), isEmpty);

      final big = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 0xAB);
      final blob = await crypto.seal(big, 'pwd');
      expect(await crypto.open(blob, 'pwd'), equals(big));
    });

    test('⑦ looksEncrypted 只看文件头：太短/随机字节都为假', () async {
      final crypto = fastCrypto();
      expect(crypto.looksEncrypted(<int>[]), isFalse);
      expect(crypto.looksEncrypted(Uint8List(200)), isFalse);
      final blob = await crypto.seal(<int>[1, 2, 3], 'pwd');
      expect(crypto.looksEncrypted(blob), isTrue);
    });

    test('⑧ 容器自带盐长度校验：传入非法盐要当场报错而不是静默降级', () async {
      final crypto = fastCrypto();
      expect(
        () => crypto.seal(<int>[1], 'pwd', salt: <int>[1, 2, 3]),
        throwsArgumentError,
      );
    });
  });

  group('应用锁', () {
    test('① 初始状态：未设置，任何密码都验证不过', () async {
      final lock = AppLockService(InMemorySecretStore(), crypto: fastCrypto());

      expect(await lock.isSet, isFalse);
      expect(await lock.verify('随便什么'), isFalse);
    });

    test('② 设置后：正确密码通过、错误密码不通过', () async {
      final lock = AppLockService(InMemorySecretStore(), crypto: fastCrypto());
      await lock.setPassword('1234');

      expect(await lock.isSet, isTrue);
      expect(await lock.verify('1234'), isTrue);
      expect(await lock.verify('12345'), isFalse);
    });

    test('③ 改密码：旧密码不对时不生效（捡到解锁手机改不了密码）', () async {
      final lock = AppLockService(InMemorySecretStore(), crypto: fastCrypto());
      await lock.setPassword('old');

      expect(await lock.changePassword('wrong', 'new'), isFalse);
      expect(await lock.verify('old'), isTrue, reason: '改密码失败不该破坏原密码');

      expect(await lock.changePassword('old', 'new'), isTrue);
      expect(await lock.verify('new'), isTrue);
      expect(await lock.verify('old'), isFalse);
    });

    test('④ 关闭应用锁后彻底不可验证', () async {
      final lock = AppLockService(InMemorySecretStore(), crypto: fastCrypto());
      await lock.setPassword('1234');
      await lock.clear();

      expect(await lock.isSet, isFalse);
      expect(await lock.verify('1234'), isFalse);
    });

    test('⑤ 空密码不允许设置', () async {
      final lock = AppLockService(InMemorySecretStore(), crypto: fastCrypto());
      expect(() => lock.setPassword(''), throwsArgumentError);
    });

    test('⑥ verifier 里不含口令明文', () async {
      final store = InMemorySecretStore();
      final lock = AppLockService(store, crypto: fastCrypto());
      await lock.setPassword('super-secret-pwd');

      final stored = await store.read(AppLockService.keyVerifier);
      expect(stored, isNotNull);
      // 存的是一份密文容器（base64），任何形式的口令都不该出现在里面
      expect(stored, isNot(contains('super-secret-pwd')));
      // 存的是一份自描述密文容器，文件头就是 magic
      final storedBytes = base64Decode(stored!);
      expect(
        storedBytes.sublist(0, CryptoService.magic.length),
        CryptoService.magic,
      );
    });
  });

  group('安全存储降级', () {
    test('① flutter test 里没有原生插件：读返回 null，写抛 storage 异常', () async {
      // 这一步守住" SecretStore 必须能降级"这条约定：
      // 读失败必须是安静的 null（上层按"没设置"处理），
      // 写失败必须出声（否则用户以为设上了，下次启动却没了）。
      final store = SecureSecretStore();
      expect(await store.read('any'), isNull);
      expect(
        () => store.write('any', 'value'),
        throwsA(
          isA<SecurityException>()
              .having((e) => e.kind, 'kind', SecurityErrorKind.storage),
        ),
      );
    });

    test('② 内存实现可用于测试：读写删都生效', () async {
      final store = InMemorySecretStore();
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      await store.delete('k');
      expect(await store.read('k'), isNull);
    });
  });
}
