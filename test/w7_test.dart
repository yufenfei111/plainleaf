import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:drift/drift.dart' show Value;
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/storage/media_storage.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_filter.dart';
import 'package:plainleaf/features/timeline/domain/timeline_grouping.dart';
import 'package:uuid/uuid.dart';

/// W7 验收测试：月分组与筛选（#21）/ 置顶（#22）/ 回收站硬删（#23）/ 缩略图补齐（#24）
final _root = Directory.systemTemp.createTempSync('plainleaf_w7');

List<int> _makeJpg(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(120, 180, 90));
  return img.encodeJpg(image, quality: 90);
}

/// 构造领域实体（分组是纯函数，不必经过数据库）
TimelineEntry _entry(
  int id, {
  EntryType type = EntryType.note,
  bool pinned = false,
  DateTime? date,
  int? notebookId,
  String title = '记录',
}) {
  final d = date ?? DateTime(2026, 9, 21);
  return TimelineEntry(
    id: id,
    uuid: 'u$id',
    title: title,
    plainText: '正文',
    type: type,
    status: EntryStatus.normal,
    pinned: pinned,
    entryDate: d,
    updatedAt: d,
    notebookId: notebookId,
  );
}

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePaths(_root.path);
  });

  late PlainLeafDatabase db;
  late LocalTimelineRepository repo;

  setUp(() {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
    repo = LocalTimelineRepository(
      db.entriesDao,
      assetsDao: db.assetsDao,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('月分组（issue #21）', () {
    test('同月合并、跨月切分，月头带条数', () {
      final groups = groupByMonth([
        _entry(1, date: DateTime(2026, 9, 21)),
        _entry(2, date: DateTime(2026, 9, 3)),
        _entry(3, date: DateTime(2026, 8, 31)),
        _entry(4, date: DateTime(2025, 12, 1)),
      ]);

      expect(groups.map((g) => g.label),
          ['2026年09月', '2026年08月', '2025年12月']);
      expect(groups.first.count, 2);
      expect(groups[1].count, 1);
    });

    test('同日合并成一个日锚点，不同日分开', () {
      final groups = groupByMonth([
        _entry(1, date: DateTime(2026, 9, 21)),
        _entry(2, date: DateTime(2026, 9, 21)),
        _entry(3, date: DateTime(2026, 9, 20)),
      ]);
      expect(groups.first.days.length, 2);
      expect(groups.first.days.first.items.length, 2);
      expect(groups.first.days.first.label, contains('09月21日'));
    });

    test('置顶项抽成独立分组且排在最前，不按月份切碎', () {
      final groups = groupByMonth([
        _entry(1, date: DateTime(2026, 9, 21), pinned: true),
        _entry(2, date: DateTime(2026, 8, 1)),
        _entry(3, date: DateTime(2026, 7, 1), pinned: true),
      ]);
      expect(groups.first.label, '置顶');
      expect(groups.first.pinned, isTrue);
      expect(groups.first.count, 2);
      expect(groups[1].label, '2026年08月');
    });
  });

  group('筛选下推到 SQL（issue #21）', () {
    Future<int> mkNotebook(String name) => db
        .into(db.notebooks)
        .insert(NotebooksCompanion.insert(
            uuid: const Uuid().v4(), name: Value(name)));

    test('按笔记本筛选：只返回该笔记本的条目', () async {
      final life = await mkNotebook('生活');
      final study = await mkNotebook('学习');
      await repo.saveEntry(
          EntryDraft(title: '生活A', plainText: 'a', notebookId: life));
      await repo.saveEntry(
          EntryDraft(title: '学习B', plainText: 'b', notebookId: study));

      final list = await repo
          .watchTimeline(filter: TimelineFilter(notebookId: study))
          .first;
      expect(list.map((e) => e.title), ['学习B']);
      expect(list.first.notebookName, '学习');
    });

    test('按类型筛选 + 仅看置顶可叠加', () async {
      final a = await repo.saveEntry(const EntryDraft(
          title: '日记A', plainText: 'a', type: EntryType.diary));
      await repo.saveEntry(const EntryDraft(
          title: '日记B', plainText: 'b', type: EntryType.diary));
      await repo.saveEntry(const EntryDraft(title: '速记C', plainText: 'c',
          type: EntryType.quick));

      final diaries = await repo
          .watchTimeline(filter: const TimelineFilter(type: EntryType.diary))
          .first;
      expect(diaries.map((e) => e.title), contains('日记A'));
      expect(diaries.length, 2);

      await repo.setPinned(a, pinned: true);
      final pinnedDiary = await repo.watchTimeline(
        filter: const TimelineFilter(type: EntryType.diary, pinnedOnly: true),
      ).first;
      expect(pinnedDiary.map((e) => e.title), ['日记A']);
    });

    test('筛选为空时不误伤：先 where 再 limit（不会被 100 条截断）', () async {
      for (var i = 0; i < 5; i++) {
        await repo.saveEntry(EntryDraft(title: '笔记$i', plainText: 'x$i'));
      }
      await repo.saveEntry(const EntryDraft(
          title: '唯一速记', plainText: 'z', type: EntryType.quick));

      final quicks = await repo
          .watchTimeline(filter: const TimelineFilter(type: EntryType.quick))
          .first;
      expect(quicks.map((e) => e.title), ['唯一速记']);
    });
  });

  group('置顶收藏（issue #22）', () {
    test('置顶后出现在「仅看置顶」，取消后消失', () async {
      final id = await repo.saveEntry(const EntryDraft(title: '要置顶', plainText: 'x'));
      await repo.saveEntry(const EntryDraft(title: '普通', plainText: 'y'));

      await repo.setPinned(id, pinned: true);
      var pinned = await repo
          .watchTimeline(filter: const TimelineFilter(pinnedOnly: true))
          .first;
      expect(pinned.map((e) => e.title), ['要置顶']);

      await repo.setPinned(id, pinned: false);
      pinned = await repo
          .watchTimeline(filter: const TimelineFilter(pinnedOnly: true))
          .first;
      expect(pinned, isEmpty);
    });

    test('置顶项排在时间轴最前（置顶优先于日期倒序）', () async {
      final old = await repo.saveEntry(const EntryDraft(title: '旧的', plainText: 'a'));
      await repo.saveEntry(const EntryDraft(title: '新的', plainText: 'b'));
      await repo.setPinned(old, pinned: true);

      final list = await repo.watchTimeline().first;
      expect(list.first.title, '旧的');
      expect(list.first.pinned, isTrue);
    });
  });

  group('回收站永久删除（issue #23）', () {
    test('硬删：条目与 FTS、标签关联一并清除，回收站不再显示', () async {
      final id = await repo.saveEntry(const EntryDraft(title: '待销毁', plainText: '关键词甲乙'));
      final tagId = await db.tagsDao.create(uuid: const Uuid().v4(), name: '临时标签');
      await db.tagsDao.tagEntry(id, tagId);

      await repo.softDelete(id);
      expect(await repo.watchTrash().first, hasLength(1));

      await repo.hardDelete(id);

      expect(await repo.watchTrash().first, isEmpty);
      // 物理行已消失（不是软删）
      expect(await db.entriesDao.findById(id), isNull);
      // FTS 不残留，否则搜索会命中已删条目
      expect(await repo.searchIds('关键词甲乙'), isNot(contains(id)));
      // 关联标签行已清理（外键约束下必须先行处理）
      expect(await db.tagsDao.tagsOfEntry(id), isEmpty);
    });

    test('清空回收站：返回清理条数且整体清空', () async {
      final a = await repo.saveEntry(const EntryDraft(title: 'A', plainText: 'a'));
      final b = await repo.saveEntry(const EntryDraft(title: 'B', plainText: 'b'));
      await repo.softDelete(a);
      await repo.softDelete(b);

      final n = await repo.emptyTrash();
      expect(n, 2);
      expect(await repo.watchTrash().first, isEmpty);
      expect(await db.entriesDao.findById(a), isNull);
      expect(await db.entriesDao.findById(b), isNull);
    });

    test('硬删后关联图片资产转为软删（相册不再出现孤儿图）', () async {
      final entryId = await repo.saveEntry(const EntryDraft(title: '带图', plainText: 'x'));
      final assetId = await db.assetsDao.attach(
        uuid: const Uuid().v4(),
        entryId: entryId,
        kind: 'image',
        relPath: 'media/2026/09/test.jpg',
      );

      await repo.softDelete(entryId);
      await repo.hardDelete(entryId);

      // byEntry 会过滤掉已删行，这里直接按 id 查原始行验证软删标记
      final rows =
          await (db.select(db.assets)..where((a) => a.id.equals(assetId))).get();
      expect(rows.single.deleted, isTrue);
    });
  });

  group('历史缩略图补齐（issue #24）', () {
    test('backfillDerived 为缺 thumb 的资产补齐并落盘', () async {
      final repoWithMedia = LocalTimelineRepository(
        db.entriesDao,
        assetsDao: db.assetsDao,
        mediaStorage: MediaStorage(),
      );
      final entryId =
          await repo.saveEntry(const EntryDraft(title: '老记录', plainText: 'x'));

      final dir = Directory.systemTemp.createTempSync('pl_w7_src');
      addTearDown(() => dir.deleteSync(recursive: true));
      final src = File(p.join(dir.path, 'src.jpg'))
        ..writeAsBytesSync(_makeJpg(800, 600));

      final rel = await MediaStorage().importFile(src.path);
      await db.assetsDao.attach(
        uuid: const Uuid().v4(),
        entryId: entryId,
        kind: 'image',
        relPath: rel,
      );

      final done = await repoWithMedia.backfillDerived();
      expect(done, 1);

      final rows = await db.assetsDao.byEntry(entryId);
      expect(rows.first.thumbPath, isNotNull);
      final thumb = await MediaStorage().resolve(rows.first.thumbPath!);
      expect(thumb.existsSync(), isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
