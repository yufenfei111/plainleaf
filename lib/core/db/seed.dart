import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

/// 阶段 0 演示种子数据：首启幂等写入，让 5 Tab 不是纯空白壳。
/// 真实数据从 W3 编辑器接入后产生；幂等标记 settings_kv.seed_v1。
class DemoSeed {
  DemoSeed._();

  static const _flagKey = 'seed_v1';

  static Future<void> maybeSeed(PlainLeafDatabase db) async {
    final flag = await (db.select(db.settingsKv)
          ..where((s) => s.key.equals(_flagKey)))
        .getSingleOrNull();
    if (flag != null) return;

    const uuidGen = Uuid();
    final now = DateTime.now();

    await db.batch((b) {
      b.insert(
        db.notebooks,
        NotebooksCompanion.insert(
          uuid: uuidGen.v4(),
          name: const Value('生活空间'),
          space: const Value('life'),
          sortIndex: const Value(0),
        ),
        mode: InsertMode.insertOrIgnore,
      );
      b.insert(
        db.notebooks,
        NotebooksCompanion.insert(
          uuid: uuidGen.v4(),
          name: const Value('学习空间'),
          space: const Value('study'),
          sortIndex: const Value(1),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });

    final notebooks = await db.select(db.notebooks).get();
    final lifeId = notebooks.firstWhere((n) => n.space == 'life').id;
    final studyId = notebooks.firstWhere((n) => n.space == 'study').id;

    await db.batch((b) {
      b.insert(
        db.entries,
        EntriesCompanion.insert(
          uuid: uuidGen.v4(),
          notebookId: Value(lifeId),
          type: const Value('diary'),
          title: const Value('阶段 0 启动'),
          plainText: const Value('空壳工程跑通了：五 Tab + 数据库就位。'),
          mood: const Value(4),
          entryDate: Value(now),
        ),
      );
      b.insert(
        db.entries,
        EntriesCompanion.insert(
          uuid: uuidGen.v4(),
          notebookId: Value(studyId),
          type: const Value('note'),
          title: const Value('高数课堂笔记'),
          plainText: const Value('级数收敛性判定：比较判别法、比值判别法。'),
          mood: const Value(3),
          entryDate: Value(now.subtract(const Duration(days: 1))),
        ),
      );
      b.insert(
        db.entries,
        EntriesCompanion.insert(
          uuid: uuidGen.v4(),
          notebookId: Value(lifeId),
          type: const Value('quick'),
          title: const Value('速记'),
          plainText: const Value('取快递：菜鸟驿站 3-2-1102。'),
          entryDate: Value(now.subtract(const Duration(days: 2))),
        ),
      );
      b.insert(
        db.entries,
        EntriesCompanion.insert(
          uuid: uuidGen.v4(),
          notebookId: Value(studyId),
          type: const Value('todo'),
          title: const Value('学习待办'),
          plainText: const Value('复习 W1 Dart 基础。'),
          entryDate: Value(now.subtract(const Duration(days: 3))),
        ),
      );
    });

    await db.batch((b) {
      b.insert(
        db.todos,
        TodosCompanion.insert(
          uuid: uuidGen.v4(),
          content: '完成阶段 0 骨架验收',
          priority: const Value(2),
        ),
      );
      b.insert(
        db.todos,
        TodosCompanion.insert(
          uuid: uuidGen.v4(),
          content: 'W2：Repository + FTS5 搜索',
          priority: const Value(1),
        ),
      );
    });

    await db.into(db.settingsKv).insert(
          SettingsKvCompanion.insert(key: _flagKey, value: const Value('1')),
          mode: InsertMode.insertOrIgnore,
        );
  }
}