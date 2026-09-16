import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// W3 记录生命周期测试：更新双写 / 草稿流转 / 回收恢复 / 30 天清理（issue #5/#6）
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

  test('updateEntry 事务双写：内容更新后 FTS 同步、version 递增', () async {
    final id = await repo.saveEntry(
        const EntryDraft(title: '初稿标题', plainText: '初稿内容'));

    await repo.updateEntry(
      id,
      const EntryDraft(title: '改后标题', plainText: '改后内容甲'),
    );

    final row =
        await (db.select(db.entries)..where((e) => e.id.equals(id))).getSingle();
    expect(row.title, '改后标题');
    expect(row.version, 2);

    // 旧内容不再命中，新内容命中
    expect(await repo.searchIds('初稿标题'), isEmpty);
    expect(await repo.searchIds('改后标题'), contains(id));
  });

  test('草稿流转：draft 不进时间轴 → 发布后出现', () async {
    final id = await repo.saveEntry(const EntryDraft(
      title: '草稿一篇',
      plainText: '还没写完',
      status: EntryStatus.draft,
    ));

    expect((await repo.watchTimeline().first).any((e) => e.id == id), isFalse);
    expect((await repo.watchDrafts().first).any((e) => e.id == id), isTrue);

    await repo.setStatus(id, status: 'normal');

    expect((await repo.watchTimeline().first).any((e) => e.id == id), isTrue);
    expect((await repo.watchDrafts().first).any((e) => e.id == id), isFalse);
  });

  test('回收站：软删出时间轴进回收站 → 恢复后回时间轴且 FTS 重建', () async {
    final id = await repo.saveEntry(
        const EntryDraft(title: '回收测试', plainText: '要被删掉的内容'));

    await repo.softDelete(id);
    expect((await repo.watchTimeline().first).any((e) => e.id == id), isFalse);
    expect((await repo.watchTrash().first).any((e) => e.id == id), isTrue);
    expect(await repo.searchIds('回收测试'), isEmpty);

    await repo.restore(id);
    expect((await repo.watchTimeline().first).any((e) => e.id == id), isTrue);
    expect((await repo.watchTrash().first).any((e) => e.id == id), isFalse);
    expect(await repo.searchIds('回收测试'), contains(id));
  });

  test('purgeExpiredTrash：仅清理超过保留期的软删行', () async {
    final freshId = await repo.saveEntry(
        const EntryDraft(title: '新删的', plainText: '刚删除不久'));
    final oldId = await repo.saveEntry(
        const EntryDraft(title: '旧删的', plainText: '早就删除了'));

    await repo.softDelete(freshId);
    await repo.softDelete(oldId);

    // 手动把 oldId 的 updatedAt 拨回 31 天前
    final cutoff = DateTime.now().subtract(const Duration(days: 31));
    await (db.update(db.entries)..where((e) => e.id.equals(oldId)))
        .write(EntriesCompanion(updatedAt: Value(cutoff)));

    final purged = await repo.purgeExpiredTrash();

    expect(purged, 1);
    // 过期行被物理删除
    final oldRow = await (db.select(db.entries)
          ..where((e) => e.id.equals(oldId)))
        .getSingleOrNull();
    expect(oldRow, isNull);
    // 未过期软删行保留在回收站
    final freshRow = await (db.select(db.entries)
          ..where((e) => e.id.equals(freshId)))
        .getSingle();
    expect(freshRow.deleted, true);
  });
}