import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/open.dart';

import '../core/db/database.dart';

/// 全局数据库单例（Riverpod 注入）
/// 分层红线：页面不直接触碰 DAO/文件系统，一律经由本 Provider 暴露的 Stream。
/// 测试覆盖方式：ProviderScope(overrides: [dbProvider.overrideWithValue(内存库)])
final dbProvider = Provider<PlainLeafDatabase>((ref) {
  final db = PlainLeafDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 测试/演示专用：宿主机内存库
/// Windows x64 的 Flutter SDK 不自带 sqlite3.dll（FTS5 需系统提供）。
/// 查找顺序：环境变量 PLAINLEAF_SQLITE3_DLL（指向完整路径）→ System32 → Git 目录。
/// CI（Linux）安装 libsqlite3-dev 后自动可用，无需此覆盖。
QueryExecutor openInMemoryDb() {
  if (Platform.isWindows) {
    final candidates = <String>[
      if (Platform.environment['PLAINLEAF_SQLITE3_DLL'] != null)
        Platform.environment['PLAINLEAF_SQLITE3_DLL']!,
      r'C:\Windows\System32\sqlite3.dll',
      r'C:\Program Files\Git\mingw64\bin\sqlite3.dll',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        open.overrideFor(
            OperatingSystem.windows, () => DynamicLibrary.open(path));
        break;
      }
    }
  }
  return NativeDatabase.memory();
}