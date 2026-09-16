import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

/// 演示种子数据：整只种子在单个事务内写入（条目含 FTS 双写），
/// 幂等标记 settings_kv.seed_v1 与数据同事务落库——要么全有，要么全无。
/// 真实数据从 W3 编辑器接入后产生；本种子不影响验收（表结构/红线才是验收点）。
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

    await db.transaction(() async {
      final lifeId = await db.into(db.notebooks).insert(
            NotebooksCompanion.insert(
              uuid: uuidGen.v4(),
              name: const Value('生活空间'),
              space: const Value('life'),
              sortIndex: const Value(0),
            ),
          );
      final studyId = await db.into(db.notebooks).insert(
            NotebooksCompanion.insert(
              uuid: uuidGen.v4(),
              name: const Value('学习空间'),
              space: const Value('study'),
              sortIndex: const Value(1),
            ),
          );

      await db.entriesDao.saveEntry(
        entry: EntriesCompanion.insert(
          uuid: uuidGen.v4(),
          notebookId: Value(lifeId),
          type: const Value('diary'),
          title: const Value('阶段 0 启动'),
          plainText: const Value('空壳工程跑通了：五 Tab + 数据库就位。'),
          mood: const Value(4),
          entryDate: Value(now),
        ),
        ftsTitle: '阶段 0 启动',
        ftsContent: '空壳工程跑通了：五 Tab + 数据库就位。',
      );
      await db.entriesDao.saveEntry(
        entry: EntriesCompanion.insert(
          uuid: uuidGen.v4(),
          notebookId: Value(studyId),
          type: const Value('note'),
          title: const Value('高数课堂笔记'),
          plainText: const Value('级数收敛性判定：比较判别法、比值判别法。'),
          mood: const Value(3),
          entryDate: Value(now.subtract(const Duration(days: 1))),
        ),
        ftsTitle: '高数课堂笔记',
        ftsContent: '级数收敛性判定：比较判别法、比值判别法。',
      );
      await db.entriesDao.saveEntry(
        entry: EntriesCompanion.insert(
          uuid: uuidGen.v4(),
          notebookId: Value(lifeId),
          type: const Value('quick'),
          title: const Value('速记'),
          plainText: const Value('取快递：菜鸟驿站 3-2-1102。'),
          entryDate: Value(now.subtract(const Duration(days: 2))),
        ),
        ftsTitle: '速记',
        ftsContent: '取快递：菜鸟驿站 3-2-1102。',
      );
      await db.entriesDao.saveEntry(
        entry: EntriesCompanion.insert(
          uuid: uuidGen.v4(),
          notebookId: Value(studyId),
          type: const Value('todo'),
          title: const Value('学习待办'),
          plainText: const Value('复习 W1 Dart 基础。'),
          entryDate: Value(now.subtract(const Duration(days: 3))),
        ),
        ftsTitle: '学习待办',
        ftsContent: '复习 W1 Dart 基础。',
      );

      await db.into(db.todos).insert(
            TodosCompanion.insert(
              uuid: uuidGen.v4(),
              content: '完成阶段 0 骨架验收',
              priority: const Value(2),
            ),
          );
      await db.into(db.todos).insert(
            TodosCompanion.insert(
              uuid: uuidGen.v4(),
              content: 'W2：Repository + FTS5 搜索',
              priority: const Value(1),
            ),
          );

      await db.into(db.settingsKv).insert(
            SettingsKvCompanion.insert(
              key: _flagKey,
              value: const Value('1'),
              uuid: uuidGen.v4(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    });
  }
}