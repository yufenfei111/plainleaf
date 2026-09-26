import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/errors/app_exception.dart';
import 'package:plainleaf/core/exporter/backup_service.dart';
import 'package:plainleaf/core/security/crypto_service.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// W14 备份包加密：导出 → 识别 → 校验 → 恢复，以及"没给密码"时的正确失败方式。
final Directory _root = Directory.systemTemp.createTempSync('plainleaf_w14');

/// 低迭代 KDF：生产 10 万次，跑十几个用例太慢；
/// 这里要验的是**流程与兼容性**，不是口令强度本身。
CryptoService fastCrypto() => CryptoService(
      kdf: Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 1000, bits: 256),
    );

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePaths(_root.path);
  });

  test('① 加密备份：缺密码 / 密码错 / 密码对，三种情形必须各不相同', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = LocalTimelineRepository(db.entriesDao);
    await repo.saveEntry(
        const EntryDraft(title: '加密备份验收', plainText: '机密内容'));

    final crypto = fastCrypto();
    final service = BackupService(db, crypto: crypto);
    final plbk =
        await service.exportBackup(fileName: 'enc.plbk', password: 'pwd-123');

    // 落盘的是加密容器，不是 zip：擦开头就知道
    final bytes = plbk.readAsBytesSync();
    expect(bytes.sublist(0, CryptoService.magic.length), CryptoService.magic);
    expect(crypto.looksEncrypted(bytes), isTrue);

    // 列表要能看出它是加密包——UI 靠这个决定"选中后先弹密码框"，
    // 让用户输完密码才告诉他这包是加密的，纯属浪费一次输入
    final listed = await service.listBackups();
    expect(
      listed.firstWhere((b) => b.fileName == 'enc.plbk').encrypted,
      isTrue,
    );

    // 不给密码 → 明确"需要密码"（而不是一句含糊的校验失败）
    try {
      await service.verify(plbk);
      fail('缺密码却校验通过了');
    } on SecurityException catch (error) {
      expect(error.kind, SecurityErrorKind.passwordRequired);
      expect(error.userMessage, contains('加密'));
    }

    // 密码不对 → 认证失败
    try {
      await service.verify(plbk, password: 'wrong-one');
      fail('错误密码却校验通过了');
    } on SecurityException catch (error) {
      expect(error.kind, SecurityErrorKind.authenticationFailed);
    }

    // 密码对 → 校验通过，manifest 里带加密标记
    final manifest = await service.verify(plbk, password: 'pwd-123');
    expect(manifest['app'], 'plainleaf');
    expect(manifest['encrypted'], isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('② 加密备份能完整恢复数据（含全文索引）', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    final repo = LocalTimelineRepository(db.entriesDao);
    await repo.saveEntry(
        const EntryDraft(title: '待恢复的秘密', plainText: '内容戊己庚'));
    expect(await db.entriesDao.searchEntryIds('内容戊己庚*'), isNotEmpty);

    final service = BackupService(db, crypto: fastCrypto());
    final plbk = await service.exportBackup(
        fileName: 'enc-restore.plbk', password: 'pwd-456');
    final restored = await service.restore(plbk, password: 'pwd-456');

    final db2 = PlainLeafDatabase.forTesting(NativeDatabase(restored));
    addTearDown(db2.close);
    final rows = await db2.select(db2.entries).get();
    expect(rows.any((e) => e.title == '待恢复的秘密'), isTrue);
    expect(await db2.entriesDao.searchEntryIds('内容戊己庚*'), isNotEmpty,
        reason: '恢复后 FTS 索引仍要可用');

    // 数据红线：恢复前那份自动备份始终在，且它是明文（不给自己加一道锁）
    final backups = await service.listBackups();
    expect(backups.any((b) => b.fileName.contains('before-restore')), isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('③ 明文备份包：行为与 W13 一致，只是多一个 encrypted=false', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = LocalTimelineRepository(db.entriesDao);
    await repo.saveEntry(const EntryDraft(title: '明文包', plainText: 'abc'));

    final service = BackupService(db, crypto: fastCrypto());
    final plbk = await service.exportBackup(fileName: 'plain.plbk');

    // 没传密码就不加密，这点不能因为加了功能而漂移
    expect(fastCrypto().looksEncrypted(plbk.readAsBytesSync()), isFalse);
    expect((await service.verify(plbk))['encrypted'], isFalse);
    expect(
      (await service.listBackups())
          .firstWhere((b) => b.fileName == 'plain.plbk')
          .encrypted,
      isFalse,
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
