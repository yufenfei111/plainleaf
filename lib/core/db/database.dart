import 'package:drift/drift.dart';

import 'connection.dart';
import 'daos/entries_dao.dart';
import 'daos/notebooks_dao.dart';
import 'daos/todos_dao.dart';
import 'tables.dart';

part 'database.g.dart';

/// 素页 PlainLeaf 数据库（Drift / SQLite + FTS5）
/// schemaVersion 从 1 起；任何表结构变更必须写 MigrationStep + 迁移测试（数据红线）。
@DriftDatabase(
  tables: [
    Notebooks,
    Entries,
    Assets,
    Tags,
    EntryTags,
    Todos,
    StudySessions,
    SyncMeta,
    SettingsKv,
  ],
  daos: [EntriesDao, TodosDao, NotebooksDao],
)
class PlainLeafDatabase extends _$PlainLeafDatabase {
  PlainLeafDatabase() : super(openPlainLeafDb());

  /// 测试专用构造：宿主机内存库（见 app/providers.dart openInMemoryDb）
  PlainLeafDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // entries_fts：FTS5 虚表（归档计划书 §7.2；内容镜像 entries.title/plainText）
          // W2 起 Repository 在同一事务内双写 entries + entries_fts（红线：不用 trigger）
          await customStatement(
            'CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts '
            'USING fts5(entry_id UNINDEXED, title, content_text)',
          );
        },
        // 阶段 0 无历史版本；W2+ 表结构变更在此追加 MigrationStep（禁「卸载重装」绕过）
        onUpgrade: (m, from, to) async {},
      );
}