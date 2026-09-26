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