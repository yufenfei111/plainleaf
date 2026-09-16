import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:uuid/uuid.dart';

/// W2 Repository 层测试：事务双写（§4.3 红线）、软删除语义、领域映射。
void main() {
  late PlainLeafDatabase db;
  late LocalTimelineRepository repo;

  setUp(() {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
    repo = LocalTimelineRepository(db.entriesDao);
  });

  tearDown(() async {
    await db.close();
  });

  test('saveEntry 事务双写：entries 与 entries_fts 同步写入并可检索', () async {
    final id = await repo.saveEntry(const EntryDraft(
      title: '双写测试',
      plainText: '全文索引内容甲',
    ));

    final entry =
        await (db.select(db.entries)..where((e) => e.id.equals(id))).getSingle();
    expect(entry.title, '双写测试');
    expect(entry.deleted, false);
    expect(entry.uuid.length, 36);

    final hits = await repo.searchIds('双写测试');
    expect(hits, contains(id));
  });

  test('softDelete 事务双删：软删除保留原行（version+1），时间轴与 FTS 同步消失', () async {
    final id = await repo.saveEntry(const EntryDraft(
      title: '删除测试',
      plainText: '可删文本乙',
    ));

    await repo.softDelete(id);

    final timeline = await repo.watchTimeline().first;
    expect(timeline.any((e) => e.id == id), isFalse);

    final raw =
        await (db.select(db.entries)..where((e) => e.id.equals(id))).getSingle();
    expect(raw.deleted, true);
    expect(raw.version, 2);

    expect(await repo.searchIds('删除测试'), isEmpty);
  });

  test('watchTimeline 领域映射：枚举/心情/笔记本名齐全', () async {
    final nbId = await db.into(db.notebooks).insert(NotebooksCompanion.insert(
          uuid: const Uuid().v4(),
          name: const Value('课程笔记'),
          space: const Value('study'),
        ));

    final id = await repo.saveEntry(EntryDraft(
      title: '映射测试',
      plainText: '内容丙',
      type: EntryType.diary,
      notebookId: nbId,
      mood: 4,
    ));

    final list = await repo.watchTimeline().first;
    final entity = list.firstWhere((e) => e.id == id);
    expect(entity.type, EntryType.diary);
    expect(entity.notebookName, '课程笔记');
    expect(entity.notebookSpace, 'study');
    expect(entity.mood, 4);
    expect(entity.pinned, false);
  });
}