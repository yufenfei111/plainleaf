import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift_flutter/drift_flutter.dart';

/// 数据库连接：drift_flutter 按平台自动选择私有目录
/// Android/iOS → App 支持目录；Windows → %APPDATA%
/// W14 AES-GCM 加密在此接线（isolateSetup 回调加 SqliteEncrypted）。
QueryExecutor openPlainLeafDb() => driftDatabase(name: 'plainleaf');