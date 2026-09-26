import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/security/app_lock.dart';
import '../../../../core/security/crypto_service.dart';
import '../../../../core/security/secret_store.dart';

/// 安全存储（App 默认走系统安全容器）
///
/// **测试必须 override**：flutter_secure_storage 走平台通道，
/// `flutter test` 里调用必抛 MissingPluginException。
final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

/// 加密服务（无状态，单例足够）
final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService());

/// 应用锁服务
final appLockProvider = Provider<AppLockService>((ref) {
  return AppLockService(
    ref.watch(secretStoreProvider),
    crypto: ref.watch(cryptoServiceProvider),
  );
});

/// 应用锁是否已启用。
///
/// 这里有个刻意的"坏结局优先"：安全容器读不到（缺插件、没设过、用户清了凭据）
/// 一律按**未启用**处理。宁可少一层保护，也不能让"读不到状态"变成"打不开 App"——
/// 后者会把用户自己锁在门外。
final appLockEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(appLockProvider).isSet;
  } on Object {
    return false;
  }
});

/// 应用锁写入门面（W14）
///
/// 与 `CloudBackupActions` 同一套路：页面不直接调服务，改完之后由这里
/// invalidate 状态，异常交给 UI 统一提示。
class AppLockActions {
  const AppLockActions(this._ref);

  final Ref _ref;

  AppLockService get _service => _ref.read(appLockProvider);

  Future<void> setPassword(String password) async {
    await _service.setPassword(password);
    _refresh();
  }

  /// 修改密码：旧密码不对返回 false（UI 负责提示），不做任何副作用
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    final ok = await _service.changePassword(oldPassword, newPassword);
    if (ok) _refresh();
    return ok;
  }

  Future<void> clear() async {
    await _service.clear();
    _refresh();
  }

  Future<bool> verify(String password) => _service.verify(password);

  void _refresh() => _ref.invalidate(appLockEnabledProvider);
}

final appLockActionsProvider =
    Provider<AppLockActions>((ref) => AppLockActions(ref));
