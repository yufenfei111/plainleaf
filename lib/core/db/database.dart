import 'package:drift/drift.dart';

import 'connection.dart';
import 'daos/assets_dao.dart';
import 'daos/entries_dao.dart';
import 'daos/notebooks_dao.dart';
import 'daos/tags_dao.dart';
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
  daos: [EntriesDao, TodosDao, NotebooksDao, AssetsDao, TagsDao],
)
class PlainLeafDatabase extends _$PlainLeafDatabase {
  PlainLeafDatabase() : super(openPlainLeafDb());

  /// 测试专用构造：宿主机内存库（见 app/providers.dart openInMemoryDb）
  PlainLeafDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // 防御：来自更早实验版/裸库的 tags 表可能没有 parent_id
          //（drift 对无自身版本记录的库走 onCreate；createAll 的 IF NOT EXISTS 不会补列）
          final hasParentCol = await customSelect(
                  "SELECT COUNT(*) AS c FROM pragma_table_info('tags') WHERE name = 'parent_id'",
                  readsFrom: {tags})
              .map((row) => row.read<int>('c') > 0)
              .getSingle();
          if (!hasParentCol) {
            await customStatement(
                'ALTER TABLE tags ADD COLUMN parent_id INTEGER NULL');
          }
          // W17 多格式附件：assets 表同样可能已存在但缺新列（同上裸库场景）
          final assetCols = await customSelect(
                  "SELECT name FROM pragma_table_info('assets')",
                  readsFrom: {assets})
              .map((row) => row.read<String>('name'))
              .get();
          if (!assetCols.contains('mime_type')) {
            await customStatement(
                'ALTER TABLE assets ADD COLUMN mime_type TEXT NULL');
          }
          if (!assetCols.contains('original_name')) {
            await customStatement(
                'ALTER TABLE assets ADD COLUMN original_name TEXT NULL');
          }
          // entries_fts：FTS5 虚表（归档计划书 §7.2；内容镜像 entries.title/plainText）
          // W2 起 Repository 在同一事务内双写 entries + entries_fts（红线：不用 trigger）
          await customStatement(
            'CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts '
            'USING fts5(entry_id UNINDEXED, title, content_text)',
          );
        },
        onUpgrade: (m, from, to) async {
          // v1 → v2：多级标签（issue #11）。addColumn 只增列，旧数据原样保留。
          if (from < 2) {
            await m.addColumn(tags, tags.parentId);
          }
          // v2 → v3：多格式附件（W17）。两列均可空，旧数据留空即可用 ——
          // mimeType 缺省按 kind 兜底，originalName 缺省回退到 uuid，
          // 因此**不需要任何数据回填**，加列即完成迁移。
          if (from < 3) {
            await m.addColumn(assets, assets.mimeType);
            await m.addColumn(assets, assets.originalName);
          }
        },
      );
}