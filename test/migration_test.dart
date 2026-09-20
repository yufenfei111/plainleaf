import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:plainleaf/core/db/database.dart';

/// 迁移测试（DEVELOPMENT.md §5.2 数据红线：每次 schema 变更必须配迁移测试）
/// 验证 v1 → v2：tags.parentId 加列，旧数据原样保留。
///
/// 手法：sqlite3 直连文件库手工构造 v1 形态（无 drift 版本记录，模拟裸库升级
/// 场景），写入旧数据；再用 PlainLeafDatabase(v2) 打开——走 onCreate 的
/// 防御补列路径。drift 自管库的 onUpgrade(1→2) 路径由同一 addColumn 语句覆盖。
void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      final candidates = <String>[
        if (Platform.environment['PLAINLEAF_SQLITE3_DLL'] != null)
          Platform.environment['PLAINLEAF_SQLITE3_DLL']!,
        r'C:\Windows\System32\sqlite3.dll',
        r'C:\Program Files\AutoClaw\resources\python\sqlite3.dll',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          open.overrideFor(
              OperatingSystem.windows, () => DynamicLibrary.open(path));
          break;
        }
      }
    }
  });

  test('v1 → v2：parentId 加列且旧数据保留', () async {
    final tmp = Directory.systemTemp.createTempSync('plainleaf_mig');
    PlainLeafDatabase? opened;
    addTearDown(() async {
      await opened?.close();
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows 文件锁留给系统临时目录清理
      }
    });
    final dbPath = '${tmp.path}/mig.sqlite';

    // ── 1) 手工构造 v1 形态 tags 表（datetime 为 drift 的 unix 秒约定）──
    final raw = sqlite3.open(dbPath);
    raw.execute('PRAGMA user_version = 1');
    raw.execute('CREATE TABLE tags ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'uuid TEXT NOT NULL, '
        'name TEXT NOT NULL UNIQUE, '
        'color INTEGER NULL, '
        'created_at INTEGER NOT NULL, '
        'updated_at INTEGER NOT NULL, '
        'version INTEGER NOT NULL DEFAULT 1, '
        'deleted INTEGER NOT NULL DEFAULT 0, '
        'UNIQUE (uuid))');
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    raw.execute(
        "INSERT INTO tags (uuid, name, created_at, updated_at) "
        "VALUES ('uuid-old-1', '旧标签', $ts, $ts)");
    raw.dispose();

    // ── 2) v2 PlainLeafDatabase 打开 → 补列 → 断言 ──
    final db = PlainLeafDatabase.forTesting(NativeDatabase(File(dbPath)));
    opened = db;

    final rows = await db.select(db.tags).get();
    expect(rows, hasLength(1));
    expect(rows.first.name, '旧标签');
    expect(rows.first.parentId, isNull);

    await (db.update(db.tags)..where((t) => t.id.equals(rows.first.id)))
        .write(TagsCompanion(parentId: Value(5)));
    final updated = await (db.select(db.tags)
          ..where((t) => t.id.equals(rows.first.id)))
        .getSingle();
    expect(updated.parentId, 5);
  });
}
