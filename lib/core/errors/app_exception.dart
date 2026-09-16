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