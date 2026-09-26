/// 素页统一异常层（DEVELOPMENT.md §5.2 错误三层透传：
/// 数据层抛领域异常 → Riverpod 转 AsyncError → UI 统一 SnackBar/空态）。
sealed class PlainLeafException implements Exception {
  const PlainLeafException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 数据层异常：DAO / 文件系统 / 同步操作失败时由 Repository 包装抛出。
class DatabaseException extends PlainLeafException {
  const DatabaseException(super.message, {this.cause});

  /// 原始异常（调试用，不直接展示给用户）。
  final Object? cause;
}

/// 导出失败（W14：PDF 缺中文字体、目标目录不可写等）
///
/// 单独建一类而不是复用 FileSystemException：导出的失败基本都源自"这台设备
/// 缺某个前提条件"，UI 需要把它和用户数据本身的问题区分开来说人话。
class ExportException extends PlainLeafException {
  const ExportException(super.message);
}

/// 安全相关失败的分类（W14 AES-GCM 加密 / 应用锁）
enum SecurityErrorKind {
  /// GCM 认证没通过。密码错误、文件被截断、被人改过一个字节，现象完全一致
  /// （见 [SecurityException.userMessage]）——**不要分开三种文案**。
  authenticationFailed,

  /// 数据是加密的，但调用方没有给密码。
  /// 与 authenticationFailed 分开的意义：UI 收到这个才去弹密码框，
  /// 收到那个则是"你刚输错了"。
  passwordRequired,

  /// 数据不是素页的加密容器（缺文件头或版本不符）
  notEncrypted,

  /// 设备安全容器（Keystore / Keychain / DPAPI）不可用。
  /// 与上面两类分开是因为用户的下一步完全不同：这类要去系统设置，再试密码没用。
  storage,
}

/// 安全层异常（W14）
///
/// [message] 记日志用；UI 一律展示 [userMessage]，
/// 且不透出 [cause]（可能带 key 名与平台堆栈）。
class SecurityException extends PlainLeafException {
  const SecurityException(
    super.message, {
    this.kind = SecurityErrorKind.authenticationFailed,
    this.cause,
  });

  final SecurityErrorKind kind;

  /// 原始异常（调试用，不直接展示给用户）。
  final Object? cause;

  String get userMessage => switch (kind) {
        SecurityErrorKind.authenticationFailed =>
          '密码不正确，或者这份数据已被改动过',
        SecurityErrorKind.passwordRequired => '这份备份包是加密的，请输入密码',
        SecurityErrorKind.notEncrypted => '这不是素页的加密数据，请确认所选文件',
        SecurityErrorKind.storage => '设备安全存储不可用，请重启应用后再试',
      };
}

/// 网络错误分类（W13 WebDAV 单向备份）
///
/// **为什么要细分而不是合成一句 message**：三类失败用户该做的动作完全不同——
/// 401 要回去改密码、超时要换网络重试、404 是云端还没有备份。若只留字符串，
/// UI 就只能把原始异常串显示出来，等于给用户看堆栈（违反项目错误透传约定）。
enum NetworkErrorKind {
  /// 连不上：DNS 失败、连接被拒、证书不受信
  offline,

  /// 401/403：账号或密码不对
  unauthorized,

  /// 404：远端没有这个文件或目录
  notFound,

  /// 超时
  timeout,

  /// 5xx：服务端出错
  server,

  /// 响应不符合预期（不是 WebDAV、内容损坏）
  protocol,
}

/// 网络层异常（W13）
///
/// [message] 记日志用（可含技术细节）；UI 一律展示 [userMessage]，
/// 绝不把 [cause]（含 URL 与可能的凭据上下文）透给用户。
class NetworkException extends PlainLeafException {
  const NetworkException(
    super.message, {
    this.kind = NetworkErrorKind.protocol,
    this.statusCode,
    this.cause,
  });

  final NetworkErrorKind kind;

  /// HTTP 状态码（无响应时为 null）
  final int? statusCode;

  /// 原始异常（调试用）
  final Object? cause;

  /// 面向用户的一句话文案，按分类给出「下一步该做什么」，不含技术细节。
  String get userMessage => switch (kind) {
        NetworkErrorKind.offline => '连不上服务器，请检查网络与服务器地址',
        NetworkErrorKind.unauthorized => '账号或密码不正确，请重新填写',
        NetworkErrorKind.notFound => '服务器上找不到该文件或目录，请检查备份目录',
        NetworkErrorKind.timeout => '服务器响应超时，请稍后重试',
        NetworkErrorKind.server => '服务器出错了，请稍后重试',
        NetworkErrorKind.protocol => '服务器返回的内容无法识别，请确认这是 WebDAV 目录',
      };
}