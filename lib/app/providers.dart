import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/open.dart';

import '../core/db/database.dart';
import '../core/storage/media_storage.dart';

/// 媒体私有目录服务（W4；路径约定 §4.3）
final mediaStorageProvider =
    Provider<MediaStorage>((ref) => MediaStorage());

/// App 支持目录的绝对路径（W6 性能改造）
/// 目的：列表卡片要「同步」把库内相对路径拼成绝对路径。
/// 此前每张卡都用 FutureBuilder 现解析一次，滑动时反复重建 Future
/// （且首帧必然是 loading 圈再跳变）——改成顶层取一次、往下传字符串，
/// 卡片里就是一次纯字符串拼接，不再有异步与跳变。
final supportDirProvider = FutureProvider<String>((ref) async {
  final dir = await ref.watch(mediaStorageProvider).supportDir();
  return dir.path;
});

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