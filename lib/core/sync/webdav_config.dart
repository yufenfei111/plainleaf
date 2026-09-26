import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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

/// WebDAV 凭据存储（W13）
///
/// **为什么不用 `settings_kv`（数据库）**：settings_kv 会随 `.plbk` 备份包一起
/// **上传到云端**——把云盘口令写进要上传的那个包里，等于每次备份都在给远端
/// 递钥匙。这里改成写支持目录根部的独立文件 `webdav.json`：
/// `BackupService` 只打包 `media/` 与 `thumb/`，该文件天然不会被带进备份包
/// （`test/w13_webdav_test.dart` 里有断言守住这条）。
///
/// **已知取舍**：文件本身仍是明文。本机没有可用的安全存储依赖，本轮也不新增
/// 依赖；等 W14 落地 AES-GCM 后再把这里升级为加密存储。明文范围已被限制在
/// 应用私有目录内、且不随备份外传。
class WebDavConfigStore {
  WebDavConfigStore({MediaStorage? mediaStorage})
      : _media = mediaStorage ?? MediaStorage();

  /// 放在支持目录根部（与 media/ thumb/ medium/ 平级），因此不进备份包
  static const fileName = 'webdav.json';

  final MediaStorage _media;

  Future<File> _file() async {
    final dir = await _media.supportDir();
    return File(p.join(dir.path, fileName));
  }

  Future<WebDavConfig?> read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final raw = jsonDecode(await file.readAsString());
      return WebDavConfig.fromJson(raw);
    } on Object {
      // 文件损坏/被删都按"未配置"处理：配置读不出来只该让用户重新填一次，
      // 不该升级成启动失败。
      return null;
    }
  }

  Future<void> write(WebDavConfig config) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
  }

  /// 清除配置（不物理删库，只删这个文件）
  Future<void> clear() async {
    final file = await _file();
    if (file.existsSync()) await file.delete();
  }
}
