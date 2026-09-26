import 'dart:convert';

import '../errors/app_exception.dart';
import 'crypto_service.dart';
import 'secret_store.dart';

/// 应用锁（W14）
///
/// **存什么**：不存密码，也不存密码的哈希，存的是「用该密码加密一个已知明文」
/// 得到的密文（verifier）。校验时对输入密码做同一件事，能解开即通过。
/// 为什么不直接存 PBKDF2 摘要：① 复用 CryptoService 的盐/迭代/容器解析，
/// 只有一条代码路径需要审计；② 将来要调迭代次数时，verifier 自带参数，
/// 老用户不必被迫重设密码（摘要方案会把所有人一次性踢下线）。
///
/// **不是什么**：应用锁**不加密数据库**。本地库文件仍是明文，能读文件就能读数据。
/// 它防的是"手机被借用时被人顺手翻两下"，不是"设备被取证"。
/// 这句话必须如实写给用户看——把应用锁宣传成数据加密是在害人。
/// 真正的数据加密走备份包加密选项（BackupService 的 encrypted 分支）。
class AppLockService {
  AppLockService(this._store, {CryptoService? crypto})
      : _crypto = crypto ?? CryptoService();

  /// verifier 在安全容器里的键名
  static const String keyVerifier = 'app_lock.verifier';

  /// 校验用已知明文。内容与用户数据无关，只需能证明"两次用的是同一把密钥"
  static const String _probeText = 'plainleaf-app-lock-v1';

  final SecretStore _store;
  final CryptoService _crypto;

  /// 是否已设置应用锁（读不到即为未设置）
  Future<bool> get isSet async => await _store.read(keyVerifier) != null;

  /// 设置（或重设）密码
  Future<void> setPassword(String password) async {
    if (password.isEmpty) {
      throw ArgumentError.value(password, 'password', '密码不能为空');
    }
    final blob = await _crypto.seal(utf8.encode(_probeText), password);
    await _store.write(keyVerifier, base64Encode(blob));
  }

  /// 修改密码：必须先验证旧密码通过，避免"捡到已解锁的手机"直接改掉密码
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    if (!await verify(oldPassword)) return false;
    await setPassword(newPassword);
    return true;
  }

  /// 关闭应用锁（删除 verifier；此后 verify 一律返回 false）
  Future<void> clear() => _store.delete(keyVerifier);

  /// 校验密码。**只处理"密码不对"这一类失败**返回 false，
  /// 其余（容器坏了、安全容器不可用）照常抛——那是 bug 或环境问题，不是密码问题。
  Future<bool> verify(String password) async {
    final raw = await _store.read(keyVerifier);
    if (raw == null || raw.isEmpty) return false;
    final clearText = await _openVerifier(raw, password);
    return utf8.decode(clearText) == _probeText;
  }

  Future<List<int>> _openVerifier(String raw, String password) async {
    try {
      return await _crypto.open(base64Decode(raw), password);
    } on SecurityException catch (error) {
      if (error.kind == SecurityErrorKind.authenticationFailed) {
        return const <int>[];
      }
      rethrow;
    }
  }
}
