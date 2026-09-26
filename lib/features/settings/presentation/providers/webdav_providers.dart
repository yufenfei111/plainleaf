import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/exporter/backup_service.dart';
import '../../../../core/sync/cloud_backup_service.dart';
import '../../../../core/sync/webdav_client.dart';
import '../../../../core/sync/webdav_config.dart';

/// 凭据存储（不入库，见 WebDavConfigStore 的说明）
final webdavConfigStoreProvider = Provider<WebDavConfigStore>((ref) {
  return WebDavConfigStore(mediaStorage: ref.watch(mediaStorageProvider));
});

/// 云端备份服务
final cloudBackupServiceProvider = Provider<CloudBackupService>((ref) {
  return CloudBackupService(
    backupService: BackupService(ref.watch(dbProvider)),
    configStore: ref.watch(webdavConfigStoreProvider),
  );
});

/// 已保存的配置（未配置时为 null）
final webdavConfigProvider = FutureProvider<WebDavConfig?>((ref) {
  return ref.watch(cloudBackupServiceProvider).loadConfig();
});

/// 云备份操作状态：空闲 / 进行中 / 成功 / 失败
enum CloudBackupStatusKind { idle, working, success, failure }

/// 卡片上的状态行。
///
/// **为什么不塞进 `AsyncValue`**：云备份是"点一下做一件事"的一次性动作，
/// 不是随数据变化的流；用 AsyncValue 会让"重载"语义把上一次的结果冲掉，
/// 而这里要的恰恰是"保留上次结果直到下一次操作"。
class CloudBackupStatus {
  const CloudBackupStatus({
    this.kind = CloudBackupStatusKind.idle,
    this.message,
  });

  final CloudBackupStatusKind kind;

  /// 面向用户的文案（失败时是 [NetworkException.userMessage]，不含堆栈）
  final String? message;

  bool get isBusy => kind == CloudBackupStatusKind.working;
}

final cloudBackupStatusProvider =
    NotifierProvider<CloudBackupStatusController, CloudBackupStatus>(
        CloudBackupStatusController.new);

class CloudBackupStatusController extends Notifier<CloudBackupStatus> {
  @override
  CloudBackupStatus build() => const CloudBackupStatus();

  void working(String text) {
    state = CloudBackupStatus(kind: CloudBackupStatusKind.working, message: text);
  }

  void success(String text) {
    state = CloudBackupStatus(kind: CloudBackupStatusKind.success, message: text);
  }

  void failure(String text) {
    state = CloudBackupStatus(kind: CloudBackupStatusKind.failure, message: text);
  }

  void reset() => state = const CloudBackupStatus();
}

/// 云备份写入门面（W13）
///
/// 与 `TimelineActions` 同一套路：页面不直接调服务，统一走这里，
/// 异常在此转成人话（[NetworkException.userMessage]）并写进状态，
/// 页面只负责"调用 + 读状态 + 必要的后续弹窗"。
class CloudBackupActions {
  // 刻意不是 const 构造：下面有一个可变字段（记录最近一次的安全失败原因）
  CloudBackupActions(this._ref);

  final Ref _ref;

  /// 最近一次云恢复失败的安全原因。
  ///
  /// 为什么要额外记一个字段，而不是让 UI 自己去 catch：这里统一把异常转成了
  /// 用户文案，UI 拿到的是一个壳（状态对象）；可"这份云端备份是加密的"这件事
  /// 需要 UI **换个动作**——弹密码框再试一次，而不是把文案显示出来就完事。
  SecurityErrorKind? _lastSecurityError;

  SecurityErrorKind? get lastSecurityError => _lastSecurityError;

  CloudBackupService get _service => _ref.read(cloudBackupServiceProvider);

  CloudBackupStatusController get _status =>
      _ref.read(cloudBackupStatusProvider.notifier);

  /// 保存配置（不测连通性，连通性交给「测试连接」）
  Future<bool> saveConfig(WebDavConfig config) async {
    if (!config.isValid) {
      _status.failure('请填写完整：地址需以 http/https 开头，账号与密码不能为空');
      return false;
    }
    try {
      await _service.saveConfig(config);
      _ref.invalidate(webdavConfigProvider);
      _status.success('配置已保存');
      return true;
    } on Object catch (error) {
      _status.failure('配置保存失败：${_message(error)}');
      return false;
    }
  }

  Future<void> clearConfig() async {
    await _service.clearConfig();
    _ref.invalidate(webdavConfigProvider);
    _status.reset();
  }

  Future<bool> testConnection(WebDavConfig config) async {
    _status.working('正在测试连接…');
    try {
      await _service.testConnection(config);
      _status.success('连接成功，可以使用这个目录');
      return true;
    } on Object catch (error) {
      _status.failure(_message(error));
      return false;
    }
  }

  /// 列出云端备份包；失败返回 null（状态里已有可操作提示）
  Future<List<WebDavResource>?> listRemote(WebDavConfig config) async {
    _status.working('正在获取云端备份列表…');
    try {
      final items = await _service.listRemote(config);
      _status.reset();
      return items;
    } on Object catch (error) {
      _status.failure(_message(error));
      return null;
    }
  }

  Future<CloudBackupResult?> upload(WebDavConfig config) async {
    _status.working('正在打包并上传…');
    try {
      final result = await _service.upload(config);
      _status.success('已上传 ${result.remoteName}');
      return result;
    } on Object catch (error) {
      _status.failure(_message(error));
      return null;
    }
  }

  /// 从云端恢复；返回被替换的库文件（失败返回 null）
  ///
  /// 加密包不给密码时先失败一次并不丢面子：web 端拿到"需要密码"的异常后
  /// UI 会弹框补一次再调一次，比为了少一次往返去额外下载整个包便宜得多。
  Future<File?> restore(
    WebDavConfig config,
    WebDavResource remote, {
    String? password,
  }) async {
    _status.working('正在下载并恢复…');
    try {
      final file = await _service.restore(config, remote, password: password);
      _lastSecurityError = null;
      _status.success('已从云端恢复，请重启应用');
      return file;
    } on Object catch (error) {
      _lastSecurityError = error is SecurityException ? error.kind : null;
      _status.failure(_message(error));
      return null;
    }
  }

  /// 异常 → 用户文案。
  /// 网络异常与安全异常都自带分级文案；其余只给一句通用兜底，
  /// 绝不把含 URL/凭据上下文的原始异常串透出去。
  String _message(Object error) {
    if (error is NetworkException) return error.userMessage;
    if (error is SecurityException) return error.userMessage;
    return '操作失败，请重试';
  }
}

final cloudBackupActionsProvider =
    Provider<CloudBackupActions>((ref) => CloudBackupActions(ref));
