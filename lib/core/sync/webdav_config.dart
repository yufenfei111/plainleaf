import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/app_exception.dart';
import '../security/secret_store.dart';
import '../storage/media_storage.dart';

/// WebDAV 连接配置（服务器地址 + 账号 + 密码）
class WebDavConfig {
  const WebDavConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  /// 备份目录地址，例如 `https://dav.jianguoyun.com/dav/素页备份/`
  final String baseUrl;

  final String username;

  final String password;

  Uri? get uri => Uri.tryParse(baseUrl);

  /// 是否填写完整（不含连通性判断——那要真的发一次请求才知道）
  bool get isValid {
    final parsed = uri;
    if (parsed == null) return false;
    final schemeOk = parsed.scheme == 'http' || parsed.scheme == 'https';
    return schemeOk &&
        parsed.host.isNotEmpty &&
        username.trim().isNotEmpty &&
        password.isNotEmpty;
  }

  /// 展示用：只暴露「协议 + 主机」。
  /// 不给完整路径与账号——设置页可能被截屏/投屏，少露一点是一点。
  String get displayHost {
    final parsed = uri;
    if (parsed == null) return baseUrl;
    return '${parsed.scheme}://${parsed.host}';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
      };

  /// 解析；字段缺失或类型不对返回 null（读到一个坏文件不该崩溃，退回"未配置"）
  static WebDavConfig? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final url = raw['baseUrl'];
    final user = raw['username'];
    final pwd = raw['password'];
    if (url is! String || user is! String || pwd is! String) return null;
    return WebDavConfig(baseUrl: url, username: user, password: pwd);
  }
}

/// WebDAV 凭据存储（W13 落地，W14 升级）
///
/// **为什么不用 `settings_kv`（数据库）**：settings_kv 会随 `.plbk` 备份包一起
/// **上传到云端**——把云盘口令写进要上传的那个包里，等于每次备份都在给远端
/// 递钥匙（`test/w13_webdav_test.dart` 里有断言守住这条）。
///
/// **W14 升级：凭据改存系统安全容器**（Android Keystore / iOS Keychain / Windows
/// DPAPI）。W13 因为本机还没引依赖，只能落在私有的 `webdav.json` 里明文存，
/// 当时写下的取舍说明就是"W14 补上"。现在补上了，但要满足两条约束：
///
/// ① **不能让旧用户重新填一次**：首次读不到安全容器就去读老文件，
///    读到了立刻迁移过去、删掉明文，全过程静默。
/// ② **不能因为拿不到安全容器就废掉功能**：模拟器没设锁屏、某些桌面环境缺
///    底层存储时，写安全容器会失败——这时**退回明文文件**，并在注释里记清楚
///    明文的范围（本机私有目录、不随备份外传）。宁可信"少一层保护但能用"，
///    也不让整个云备份在部分机型上变成摆设。
class WebDavConfigStore {
  WebDavConfigStore({MediaStorage? mediaStorage, SecretStore? secretStore})
      : _media = mediaStorage ?? MediaStorage(),
        _secrets = secretStore ?? SecureSecretStore();

  /// 旧（W13）：支持目录根部的独立文件，与 media/ thumb/ medium/ 平级，
  /// 因此不进备份包。W14 起降级为兜底位置。
  static const fileName = 'webdav.json';

  /// 新：系统安全容器里的键名
  static const String secretKey = 'webdav.config';

  final MediaStorage _media;
  final SecretStore _secrets;

  Future<File> _legacyFile() async {
    final dir = await _media.supportDir();
    return File(p.join(dir.path, fileName));
  }

  Future<WebDavConfig?> read() async {
    final secure = _readJson(await _secrets.read(secretKey));
    if (secure != null) return secure;

    // 走到这里说明是老用户（或安全容器不可用），去读明文老文件
    final legacy = await _readLegacy();
    if (legacy == null) return null;
    // 顺手迁移：写进安全容器成功才删明文。迁移失败不必通知用户——
    // 下次启动还会再试一次，而凭据本身并没有丢。
    try {
      await write(legacy);
    } on Object {
      // 迁移失败保留原状
    }
    return legacy;
  }

  Future<void> write(WebDavConfig config) async {
    final json = const JsonEncoder().convert(config.toJson());
    try {
      await _secrets.write(secretKey, json);
      await _deleteLegacy();
      return;
    } on SecurityException {
      // 安全容器不可用 → 退回明文文件（理由见类注释 ②）
    }
    final file = await _legacyFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
  }

  /// 清除配置（两处都清，不物理删库）
  Future<void> clear() async {
    try {
      await _secrets.delete(secretKey);
    } on Object {
      // 删除失败无副作用（SecretStore 约定就是静默）
    }
    await _deleteLegacy();
  }

  Future<WebDavConfig?> _readLegacy() async {
    try {
      final file = await _legacyFile();
      if (!file.existsSync()) return null;
      return _readJson(await file.readAsString());
    } on Object {
      // 文件损坏/被删都按"未配置"处理：配置读不出来只该让用户重新填一次，
      // 不该升级成启动失败。
      return null;
    }
  }

  Future<void> _deleteLegacy() async {
    try {
      final file = await _legacyFile();
      if (file.existsSync()) await file.delete();
    } on Object {
      // 删不掉最坏结果只是留了一个明文副本，不值得打断用户
    }
  }

  /// 解析 owner 为 WebDavConfig；格式不对返回 null（不抛）
  WebDavConfig? _readJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return WebDavConfig.fromJson(jsonDecode(raw));
    } on Object {
      return null;
    }
  }
}
