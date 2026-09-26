import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../errors/app_exception.dart';

/// 安全键值存储抽象（W14）
///
/// 为什么要有这一层，而不是各处直接 new FlutterSecureStorage()：
/// ① flutter_secure_storage 走平台通道，`flutter test` 里调用必抛
///    MissingPluginException。应用锁的逻辑要能进 CI，就必须能把存储换掉；
/// ② 「读不到」是安全层的常态结果（首次安装、用户清过凭据、模拟器没锁屏），
///    它应该是一个安静的 null，而不是让每个调用方各自 try 一遍。
abstract class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 内存实现：测试用，也是安全容器不可用时的降级实现。
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// 系统安全容器实现（Android Keystore / iOS Keychain / Windows DPAPI）。
///
/// 三条行为约定，是刻意不一致的：
/// - **read 失败 → 返回 null**：读不到等同于"还没有"，由上层决定要不要重试；
/// - **write 失败 → 抛 SecurityException(storage)**：必须让用户知道。
///   否则"我明明设了密码"却在下一次启动被静默当成没设过，用户根本无从判断
///   是自己记错还是 App 坏了；
/// - **delete 失败 → 静默**：删不掉的最坏结果是下次还要输一次密码，
///   不值得为此打断用户。
class SecureSecretStore implements SecretStore {
  SecureSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on Object catch (error) {
      throw SecurityException(
        '写入安全存储失败：key=$key',
        kind: SecurityErrorKind.storage,
        cause: error,
      );
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on Object {
      // 刻意静默，理由见类注释第三条
    }
  }
}
