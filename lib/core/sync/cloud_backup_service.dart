import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/app_exception.dart';
import '../exporter/backup_service.dart';
import 'webdav_client.dart';
import 'webdav_config.dart';

/// 一次上传的结果（给 UI 展示"传了什么、多大"）
class CloudBackupResult {
  const CloudBackupResult({
    required this.remoteName,
    required this.sizeBytes,
    required this.localFile,
  });

  /// 云端文件名
  final String remoteName;

  final int sizeBytes;

  /// 本地同步生成的备份包（保留给用户核对路径）
  final File localFile;
}

/// 云端单向备份：上传 / 拉取 / 列目录（W13）
///
/// **分工**：本服务只做"把本地 .plbk 搬到远端、再从远端搬回来"，
/// 打包与落地一律复用 [BackupService]：
/// - 上传 = `exportBackup()` → `verify()` → PUT；
/// - 恢复 = GET → `verify()` → `BackupService.restore()`（内部已含
///   **恢复前自动备份**与既有迁移路径，不允许另写一套覆盖逻辑）。
class CloudBackupService {
  CloudBackupService({
    required BackupService backupService,
    required WebDavConfigStore configStore,
    this.timeout = const Duration(seconds: 30),
    this.httpClientFactory,
  })  : _backups = backupService,
        _configs = configStore;

  final BackupService _backups;
  final WebDavConfigStore _configs;

  /// 请求超时（透传给 [WebDavClient]）
  final Duration timeout;

  /// 仅供测试注入（例如强制 `findProxy = DIRECT`，避开测试环境的 HTTP_PROXY）
  final HttpClient Function()? httpClientFactory;

  Future<WebDavConfig?> loadConfig() => _configs.read();

  Future<void> saveConfig(WebDavConfig config) => _configs.write(config);

  Future<void> clearConfig() => _configs.clear();

  /// 测试连接：能列到目录即视为可用
  Future<void> testConnection(WebDavConfig config) async {
    final client = _client(config);
    try {
      await client.ping();
    } finally {
      client.close();
    }
  }

  /// 列出云端备份包（只保留 .plbk，最新在前）
  Future<List<WebDavResource>> listRemote(WebDavConfig config) async {
    final client = _client(config);
    try {
      final items = await client.listDirectory();
      return items.where((item) => item.isBackupPackage).toList(growable: false);
    } finally {
      client.close();
    }
  }

  /// 上传：本地打包 → **先校验** → PUT
  ///
  /// 校验放在上传前是硬要求：打包若静默失败（快照为空等），
  /// 把坏包传上去只会得到一个"看起来成功、实际恢复不了"的云端备份。
  Future<CloudBackupResult> upload(WebDavConfig config) async {
    final plbk = await _backups.exportBackup();
    try {
      await _backups.verify(plbk);
    } on Object catch (error) {
      throw NetworkException(
        '本地备份包校验失败，已中止上传',
        kind: NetworkErrorKind.protocol,
        cause: error,
      );
    }

    final bytes = plbk.readAsBytesSync();
    final remoteName = p.basename(plbk.path);
    final client = _client(config);
    try {
      // 目录不存在时顺手建出来；已存在时服务端回 405，客户端按成功处理
      await client.ensureDirectory();
      await client.putFile(remoteName, bytes);
    } finally {
      client.close();
    }
    return CloudBackupResult(
      remoteName: remoteName,
      sizeBytes: bytes.length,
      localFile: plbk,
    );
  }

  /// 恢复：下载 → 校验 → [BackupService.restore]
  ///
  /// 顺序很重要：**校验不过绝不落地**，否则一次网络损坏就会把当前数据覆盖掉。
  /// 落地后的自动备份由 `BackupService.restore` 负责（数据红线）。
  Future<File> restore(WebDavConfig config, WebDavResource remote) async {
    final client = _client(config);
    List<int> bytes;
    try {
      bytes = await client.getFile(remote.name);
    } finally {
      client.close();
    }

    final tmpDir = await Directory.systemTemp.createTemp('plainleaf_cloud');
    try {
      final file = File(p.join(tmpDir.path, p.basename(remote.name)));
      await file.writeAsBytes(bytes, flush: true);
      try {
        await _backups.verify(file);
      } on Object catch (error) {
        throw NetworkException(
          '下载到的文件不是有效的备份包，已中止恢复',
          kind: NetworkErrorKind.protocol,
          cause: error,
        );
      }
      return await _backups.restore(file);
    } finally {
      if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
    }
  }

  WebDavClient _client(WebDavConfig config) {
    final uri = config.uri;
    if (!config.isValid || uri == null) {
      throw const NetworkException(
        'WebDAV 配置不完整',
        kind: NetworkErrorKind.protocol,
      );
    }
    return WebDavClient(
      baseUrl: uri,
      username: config.username,
      password: config.password,
      timeout: timeout,
      httpClient: httpClientFactory?.call(),
    );
  }
}
