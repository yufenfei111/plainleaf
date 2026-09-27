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
/// 建 v1/v2 形态的 assets 表。
///
/// 两个版本的表结构相同（v1→v2 只动了 tags），所以共用一份 DDL。
/// **迁移测试的库必须包含「迁移会碰到的表」** —— 否则 `ALTER TABLE assets ...`
/// 会因缺表抛 `no such table`，让整个升级中断（这正是首次跑 v2→v3 时踩到的）。
void _createAssetsV1(Database raw) {
  raw.execute('CREATE TABLE assets ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'uuid TEXT NOT NULL, '
      'entry_id INTEGER NULL, '
      "kind TEXT NOT NULL DEFAULT 'image', "
      'rel_path TEXT NOT NULL, '
      'thumb_path TEXT NULL, '
      'medium_path TEXT NULL, '
      'width INTEGER NULL, '
      'height INTEGER NULL, '
      'size_bytes INTEGER NULL, '
      'duration_ms INTEGER NULL, '
      'exif_json TEXT NULL, '
      'hash_sha256 TEXT NULL, '
      'sort_index INTEGER NOT NULL DEFAULT 0, '
      'created_at INTEGER NOT NULL, '
      'updated_at INTEGER NOT NULL, '
      'version INTEGER NOT NULL DEFAULT 1, '
      'deleted INTEGER NOT NULL DEFAULT 0, '
      'UNIQUE (uuid))');
}

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
    // v1 → v3 的完整链路会动 assets 表，所以测试库必须带上它
    _createAssetsV1(raw);
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

  test('v2 → v3：assets 加 mimeType / originalName 且旧数据保留', () async {
    final tmp = Directory.systemTemp.createTempSync('plainleaf_mig3');
    PlainLeafDatabase? opened;
    addTearDown(() async {
      await opened?.close();
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows 文件锁留给系统临时目录清理
      }
    });
    final dbPath = '${tmp.path}/mig3.sqlite';

    // ── 1) 手工构造 v2 形态 assets 表（**没有** mime_type / original_name）──
    final raw = sqlite3.open(dbPath);
    raw.execute('PRAGMA user_version = 2');
    _createAssetsV1(raw);
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    raw.execute(
        "INSERT INTO assets (uuid, kind, rel_path, created_at, updated_at) "
        "VALUES ('uuid-old-asset', 'image', 'media/2026/09/old.jpg', $ts, $ts)");
    raw.dispose();

    // ── 2) v3 PlainLeafDatabase 打开 → 加列 → 断言 ──
    final db = PlainLeafDatabase.forTesting(NativeDatabase(File(dbPath)));
    opened = db;

    final rows = await db.select(db.assets).get();
    expect(rows, hasLength(1));
    // 旧数据原样保留；新列留空——因此本次迁移**不需要任何数据回填**
    expect(rows.first.relPath, 'media/2026/09/old.jpg');
    expect(rows.first.kind, 'image');
    expect(rows.first.mimeType, isNull);
    expect(rows.first.originalName, isNull);

    // 新列可写（多格式附件走的就是这条路）
    await (db.update(db.assets)..where((a) => a.id.equals(rows.first.id)))
        .write(const AssetsCompanion(
      mimeType: Value('application/pdf'),
      originalName: Value('作业第三章.pdf'),
    ));
    final updated = await (db.select(db.assets)
          ..where((a) => a.id.equals(rows.first.id)))
        .getSingle();
    expect(updated.mimeType, 'application/pdf');
    expect(updated.originalName, '作业第三章.pdf');
  });
}
