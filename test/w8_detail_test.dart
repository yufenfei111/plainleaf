import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show QuillEditor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/features/detail/presentation/entry_detail_page.dart';
import 'package:plainleaf/features/detail/presentation/providers/entry_detail_providers.dart';
import 'package:plainleaf/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/main.dart';
import 'package:uuid/uuid.dart';

/// W8 记录详情页验收
///
/// 关键点：
/// - 必须用 PlainLeafApp 承载（否则 flutter_quill 本地化 delegate 缺失会抛一堆异常）；
/// - 通过 routerConfig 注入自定义 GoRouter 隔离路由（详情页 /detail?id=N，
///   另给一个 /editor 桩以免菜单跳转时找不到路由）；
/// - supportDirProvider 用临时目录覆盖，保证图片区能拼出绝对路径用于断言
///   （不依赖宿主 path_provider 的 channel 实现，测试更确定）。
void main() {
  late PlainLeafDatabase db;
  late Directory supportDir;

  setUp(() async {
    db = PlainLeafDatabase.forTesting(openInMemoryDb());
    supportDir = Directory.systemTemp.createTempSync('plainleaf_detail');
  });

  tearDown(() async {
    await db.close();
    if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
  });

  /// 插入一条记录，返回 id（经由真实仓库，保证 FTS/映射与线上一致）
  Future<int> insertEntry(
    String title,
    String plainText, {
    String? contentDelta,
    int? mood,
    String type = 'diary',
  }) {
    final repo = LocalTimelineRepository(db.entriesDao);
    return repo.saveEntry(
      EntryDraft(
        title: title,
        plainText: plainText,
        contentDelta: contentDelta ?? '',
        mood: mood,
        type: EntryType.fromName(type),
      ),
    );
  }

  /// 给记录挂一张图：原图 media/…、medium/…、thumb/… 三档齐全
  Future<void> attachImage(int entryId) => db.assetsDao.attach(
        uuid: const Uuid().v4(),
        entryId: entryId,
        kind: 'image',
        relPath: 'media/2026/09/orig_pic.jpg',
        mediumPath: 'medium/2026/09/med_pic.jpg',
        thumbPath: 'thumb/2026/09/thumb_pic.jpg',
        width: 1600,
        height: 1200,
      );

  /// 组装详情页 Widget（注入内存库 + 临时支持目录）
  Future<void> pumpDetail(
    WidgetTester tester,
    int id, {
    List<Override> extraOverrides = const [],
  }) async {
    final router = GoRouter(
      initialLocation: '/detail?id=$id',
      routes: [
        GoRoute(
          path: '/detail',
          builder: (_, state) => EntryDetailPage(
            entryId: int.parse(state.uri.queryParameters['id']!),
          ),
        ),
        // 编辑入口跳转目标桩（测试不点，但避免路由缺失异常）
        GoRoute(
          path: '/editor',
          builder: (_, _) => const Scaffold(body: Center(child: Text('编辑器桩'))),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          supportDirProvider.overrideWith((ref) async => supportDir.path),
          ...extraOverrides,
        ],
        child: PlainLeafApp(routerConfig: router),
      ),
    );
  }

  testWidgets('① 无图记录：标题与正文正常渲染', (tester) async {
    final id = await insertEntry('测试标题', '测试正文内容');
    await pumpDetail(tester, id);
    await tester.pumpAndSettle();

    // 标题出现在 AppBar
    expect(find.text('测试标题'), findsOneWidget);
    // 正文出现在正文区（contentDelta 为空 → 静默降级为 plainText）
    expect(find.text('测试正文内容'), findsOneWidget);
    // 无图 → 页面不应出现任何 Image
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('② 有图记录：大图用的是 medium 而非原图', (tester) async {
    final id = await insertEntry('带图记录', '看图');
    await attachImage(id);
    await pumpDetail(tester, id);
    await tester.pumpAndSettle();

    // 详情页只应渲染一张图（PageView 单张）
    final images = find.byType(Image);
    expect(images, findsOneWidget);

    // cacheWidth 会把 FileImage 包成 ResizeImage，先解一层拿到真实文件路径
    final provider = tester.widget<Image>(images.first).image;
    final inner = provider is ResizeImage ? provider.imageProvider : provider;
    final file = (inner as FileImage).file;
    // 关键断言：路径里含 medium、且不含 media（说明没直接解码原图 relPath）
    expect(file.path, contains('medium'),
        reason: '详情页大图必须走 medium 派生图');
    expect(file.path, isNot(contains('media')),
        reason: '不应直接解码原图 media/');
    expect(file.path, isNot(contains('orig_pic')),
        reason: '不应回退到原图文件名');
  });

  testWidgets('③ contentDelta 非法 JSON：降级渲染 plainText 且不抛异常',
      (tester) async {
    final id = await insertEntry('坏 Delta 记录', '降级文本',
        contentDelta: '这不是合法json{');
    await pumpDetail(tester, id);
    // 若解析失败上抛，这里会直接抛异常使测试失败
    await tester.pumpAndSettle();

    expect(find.text('降级文本'), findsOneWidget,
        reason: '非法 Delta 应静默降级为 plainText');
    // 降级分支不渲染富文本编辑器
    expect(find.byType(QuillEditor), findsNothing);
  });

  testWidgets('④ id 不存在：显示「记录不存在或已被删除」', (tester) async {
    await pumpDetail(tester, 99999);
    await tester.pumpAndSettle();

    expect(find.text('记录不存在或已被删除'), findsOneWidget);
  });

  testWidgets('⑤ AppBar 存在编辑入口', (tester) async {
    final id = await insertEntry('可编辑记录', '正文');
    await pumpDetail(tester, id);
    await tester.pumpAndSettle();

    // 打开溢出菜单
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
  });

  testWidgets('⑥ loading 态出现 CircularProgressIndicator', (tester) async {
    final id = await insertEntry('加载中记录', '正文');
    // 内存库 future 解析过快，用延迟覆盖把 pending 态留住一帧，确定性验证 loading UI
    await pumpDetail(
      tester,
      id,
      extraOverrides: [
        entryDetailProvider.overrideWith((ref, arg) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return ref.watch(timelineRepositoryProvider).findEntryById(arg);
        }),
      ],
    );
    // 首帧：详情 future 尚未完成，应处于 loading
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pumpAndSettle();
    // 加载完成后 loading 圈消失，标题出现
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('加载中记录'), findsOneWidget);
  });
}
