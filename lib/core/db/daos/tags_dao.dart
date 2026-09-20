import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'tags_dao.g.dart';

@DriftAccessor(tables: [Tags, EntryTags])
class TagsDao extends DatabaseAccessor<PlainLeafDatabase>
    with _$TagsDaoMixin {
  TagsDao(super.db);

  /// 全部标签流（按名称排序）
  Stream<List<Tag>> watchAll() {
    return (select(tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  }

  /// 创建标签（重名抛 Unique 异常，由上层转领域异常）
  Future<int> create({required String uuid, required String name, int? color}) {
    return into(tags).insert(TagsCompanion.insert(
      uuid: uuid,
      name: name,
      color: Value(color),
    ));
  }

  /// 重命名
  Future<void> rename(int id, String name) {
    return transaction(() async {
      final row = await (select(tags)..where((t) => t.id.equals(id))).getSingle();
      await (update(tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          name: Value(name),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }

  /// 删除标签（软删；entry_tags 关联保留——标签回归时关联仍生效）
  Future<void> softDelete(int id) {
    return transaction(() async {
      final row = await (select(tags)..where((t) => t.id.equals(id))).getSingle();
      await (update(tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          deleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          version: Value(row.version + 1),
        ),
      );
    });
  }

  /// 条目打标 / 摘标（关联表纯操作）
  Future<void> tagEntry(int entryId, int tagId) {
    return into(entryTags).insert(
      EntryTagsCompanion.insert(entryId: entryId, tagId: tagId),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> untagEntry(int entryId, int tagId) {
    return (delete(entryTags)
          ..where((r) => r.entryId.equals(entryId) & r.tagId.equals(tagId)))
        .go();
  }

  /// 条目现有标签
  Future<List<Tag>> tagsOfEntry(int entryId) {
    final joined = select(tags).join([
      innerJoin(entryTags, entryTags.tagId.equalsExp(tags.id)),
    ])
      ..where(entryTags.entryId.equals(entryId) & tags.deleted.equals(false));
    return joined
        .map((row) => row.readTable(tags))
        .get();
  }
}