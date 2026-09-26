import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/errors/app_exception.dart';
import 'package:plainleaf/core/exporter/backup_service.dart';
import 'package:plainleaf/core/sync/cloud_backup_service.dart';
import 'package:plainleaf/core/sync/webdav_client.dart';
import 'package:plainleaf/core/sync/webdav_config.dart';
import 'package:plainleaf/features/settings/presentation/providers/webdav_providers.dart';
import 'package:plainleaf/features/settings/presentation/settings_page.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/main.dart';

/// 本机临时根：备份包、凭据文件、恢复后的库都落在这里，不污染真实私有目录。
final Directory _root = Directory.systemTemp.createTempSync('plainleaf_w13');

/// 测试环境的 HTTP_PROXY 会把 127.0.0.1 的请求也代理走，必须显式直连。
HttpClient _directClient() => HttpClient()..findProxy = (_) => 'DIRECT';

/// 空的 HttpOverrides 子类：继承来的 createHttpClient 会造出**真的** HttpClient。
class _RealHttpOverrides extends HttpOverrides {}

/// flutter_test 的 TestWidgetsFlutterBinding 会把 HttpClient 换成"一律返回 400、
/// 不真发请求"的桩（不这么做的话，测试里一个手滑就会打到真实外网）。
/// 我们要测的恰恰是真实 socket 行为，所以相关用例统一跑在这个 zone 里。
Future<void> withRealHttp(Future<void> Function() body) {
  return HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());
}

/// 假 WebDAV 服务器：记录收到的请求，按可变的 status/responseBody/delay 应答。
/// 用真实的本地 socket 而不是 mock，能顺带覆盖 dart:io 的真实行为。
class FakeDavServer {
  FakeDavServer._(this._server);

  final HttpServer _server;

  int get port => _server.port;

  /// 下一个请求的应答状态码（默认 200）
  int status = 200;

  List<int> responseBody = <int>[];

  /// 应答前延迟，用于构造超时
  Duration delay = Duration.zero;

  /// 收到的请求（方法 / 路径 / Authorization / 请求体）
  final List<FakeRequest> requests = <FakeRequest>[];

  static Future<FakeDavServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeDavServer._(server);
    server.listen((request) async {
      try {
        final chunks = BytesBuilder(copy: false);
        await for (final chunk in request) {
          chunks.add(chunk);
        }
        fake.requests.add(FakeRequest(
          request.method,
          request.uri.path,
          request.headers.value(HttpHeaders.authorizationHeader),
          chunks.takeBytes(),
        ));
        if (fake.delay > Duration.zero) {
          await Future<void>.delayed(fake.delay);
        }
        request.response.statusCode = fake.status;
        if (fake.responseBody.isNotEmpty) request.response.add(fake.responseBody);
        await request.response.close();
      } on Object {
        // 假服务器自身不因为某个请求异常而中断（例如测试已结束、连接被关）
      }
    });
    return fake;
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

  Future<void> close() => _server.close(force: true);
}

class FakeRequest {
  const FakeRequest(this.method, this.path, this.authorization, this.body);

  final String method;
  final String path;
  final String? authorization;
  final List<int> body;
}

const String _propfindXml = '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/backup/</D:href>
    <D:propstat>
      <D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/backup/plainleaf-backup-2026-09-26.plbk</D:href>
    <D:propstat>
      <D:prop>
        <D:getlastmodified>Sat, 26 Sep 2026 01:02:03 GMT</D:getlastmodified>
        <D:getcontentlength>4096</D:getcontentlength>
        <D:resourcetype/>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/backup/plainleaf-backup-2026-09-25.plbk</D:href>
    <D:propstat>
      <D:prop>
        <D:getlastmodified>Fri, 25 Sep 2026 01:02:03 GMT</D:getlastmodified>
        <D:getcontentlength>2048</D:getcontentlength>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/backup/readme.txt</D:href>
    <D:propstat>
      <D:prop><D:getcontentlength>10</D:getcontentlength></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>
''';

/// 无命名空间前缀 + 绝对 URL + 坏日期：验证解析的容错下限
const String _propfindNoPrefixXml = '''
<multistatus>
  <response>
    <href>http://127.0.0.1:65535/dav/plainleaf-backup-2026-09-26.plbk</href>
    <propstat>
      <prop><getlastmodified>not-a-date</getlastmodified></prop>
      <status>HTTP/1.1 200 OK</status>
    </propstat>
  </response>
</multistatus>
''';

WebDavConfig _config(Uri base) => WebDavConfig(
      baseUrl: base.toString(),
      username: 'alice',
      password: 'secret',
    );

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePaths(_root.path);
  });

  // ---------------------------------------------------------- XML 解析（纯函数）

  test('① PROPFIND 解析：跳过目录自身，识别 .plbk 与大小/时间', () {
    final items = WebDavClient.parsePropfind(_propfindXml, '/dav/backup');

    // 目录自身那条不出现
    expect(items.length, 3);
    expect(items.any((item) => item.isDirectory), isFalse);

    final newest =
        items.firstWhere((item) => item.name.contains('2026-09-26'));
    expect(newest.sizeBytes, 4096);
    expect(newest.modifiedAt, isNotNull);
    expect(newest.isBackupPackage, isTrue);

    final txt = items.firstWhere((item) => item.name == 'readme.txt');
    expect(txt.isBackupPackage, isFalse);
  });

  test('② PROPFIND 解析：无前缀 + 绝对 URL + 坏日期也能降级不抛', () {
    final items = WebDavClient.parsePropfind(_propfindNoPrefixXml, '/dav');

    expect(items.length, 1);
    expect(items.single.path, '/dav/plainleaf-backup-2026-09-26.plbk');
    expect(items.single.modifiedAt, isNull, reason: '坏日期降级为 null');
    expect(items.single.sizeBytes, isNull);
  });

  // ------------------------------------------------------------ 客户端错误分类

  test('③ 401 → unauthorized（提示指向改密码）', () async {
    await withRealHttp(() async {
      final server = await FakeDavServer.start();
      addTearDown(server.close);
      server.status = 401;

      final client = WebDavClient(
        baseUrl: server.url('/dav/'),
        username: 'alice',
        password: 'wrong',
        httpClient: _directClient(),
      );
      addTearDown(client.close);

      try {
        await client.ping();
        fail('应当抛出 NetworkException');
      } on NetworkException catch (error) {
        expect(error.kind, NetworkErrorKind.unauthorized);
        expect(error.statusCode, 401);
        expect(error.userMessage, contains('密码'));
      }
    });
  });

  test('④ 404 → notFound（下载一个不存在的文件）', () async {
    await withRealHttp(() async {
      final server = await FakeDavServer.start();
      addTearDown(server.close);
      server.status = 404;

      final client = WebDavClient(
        baseUrl: server.url('/dav/'),
        username: 'alice',
        password: 'secret',
        httpClient: _directClient(),
      );
      addTearDown(client.close);

      try {
        await client.getFile('missing.plbk');
        fail('应当抛出 NetworkException');
      } on NetworkException catch (error) {
        expect(error.kind, NetworkErrorKind.notFound);
      }
    });
  });

  test('⑤ 服务器不响应 → timeout', () async {
    await withRealHttp(() async {
      final server = await FakeDavServer.start();
      addTearDown(server.close);
      server.delay = const Duration(seconds: 3);

      final client = WebDavClient(
        baseUrl: server.url('/dav/'),
        username: 'alice',
        password: 'secret',
        httpClient: _directClient(),
        timeout: const Duration(milliseconds: 300),
      );
      addTearDown(client.close);

      try {
        await client.ping();
        fail('应当抛出 NetworkException');
      } on NetworkException catch (error) {
        expect(error.kind, NetworkErrorKind.timeout);
      }
    });
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('⑥ 端口没人听 → offline', () async {
    await withRealHttp(() async {
      // 先占一个端口再立刻释放，得到一个"确定连不上"的地址
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close(force: true);

      final client = WebDavClient(
        baseUrl: Uri.parse('http://127.0.0.1:$port/dav/'),
        username: 'alice',
        password: 'secret',
        httpClient: _directClient(),
        timeout: const Duration(seconds: 3),
      );
      addTearDown(client.close);

      try {
        await client.ping();
        fail('应当抛出 NetworkException');
      } on NetworkException catch (error) {
        expect(error.kind, NetworkErrorKind.offline);
      }
    });
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ---------------------------------------------------------------- 上传/列目录

  test('⑦ 上传：PUT 到备份目录、带 Basic 认证，且内容是完整 zip', () async {
    await withRealHttp(() async {
      final db = PlainLeafDatabase.forTesting(openInMemoryDb());
      addTearDown(db.close);
      await LocalTimelineRepository(db.entriesDao).saveEntry(
        const EntryDraft(title: '云端上传验收', plainText: '内容'),
      );

      final server = await FakeDavServer.start();
      addTearDown(server.close);
      server
        ..status = 201
        ..responseBody = <int>[];

      final service = CloudBackupService(
        backupService: BackupService(db),
        configStore: WebDavConfigStore(),
        httpClientFactory: _directClient,
      );

      final result = await service.upload(_config(server.url('/dav/')));

      expect(result.remoteName, endsWith('.plbk'));
      expect(result.sizeBytes, greaterThan(0));

      final put = server.requests.where((r) => r.method == 'PUT').toList();
      expect(put, hasLength(1));
      expect(put.single.path, '/dav/${result.remoteName}');
      // Basic 认证 = base64('alice:secret')
      expect(
        put.single.authorization,
        'Basic ${base64Encode(utf8.encode('alice:secret'))}',
      );
      // 上传的字节必须是一个 zip（头两字节是 PK）
      expect(utf8.decode(put.single.body.take(2).toList()), 'PK');
      // 上传前先本地校验过，所以远端拿到的包一定是可解开的
      expect(
        await BackupService(db).verify(result.localFile),
        containsPair('app', 'plainleaf'),
      );
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('⑧ 列目录：路径拼接正确、按时间倒序', () async {
    await withRealHttp(() async {
      final server = await FakeDavServer.start();
      addTearDown(server.close);
      server
        ..status = 207
        ..responseBody = utf8.encode(_propfindXml);

      final client = WebDavClient(
        baseUrl: server.url('/dav/backup'),
        username: 'alice',
        password: 'secret',
        httpClient: _directClient(),
      );
      addTearDown(client.close);

      // base 没有尾斜杠也要拼对（这是 _resolve 特意处理的场景）
      final items = await client.listDirectory();
      expect(server.requests.single.path, '/dav/backup/');
      expect(items.map((item) => item.name).toList(), [
        'plainleaf-backup-2026-09-26.plbk',
        'plainleaf-backup-2026-09-25.plbk',
        'readme.txt',
      ]);
      // 前两个是备份包，第三个不是
      expect(items[0].isBackupPackage, isTrue);
      expect(items[2].isBackupPackage, isFalse);
    });
  });

  // ------------------------------------------------------------------ 恢复流程

  test('⑨ 恢复：下载 → 校验 → 自动备份 → 覆盖（数据红线）', () async {
    await withRealHttp(() async {
      // 1) 先做一个"云端上的"备份包（含一条可识别的记录）
      final source = PlainLeafDatabase.forTesting(openInMemoryDb());
      await LocalTimelineRepository(source.entriesDao).saveEntry(
        const EntryDraft(title: '云端恢复验收', plainText: '来自云端'),
      );
      final plbk = await BackupService(source).exportBackup(fileName: 'cloud.plbk');
      final plbkBytes = plbk.readAsBytesSync();
      await source.close();

      // 2) 假服务器把它吐回来
      final server = await FakeDavServer.start();
      addTearDown(server.close);
      server
        ..status = 200
        ..responseBody = plbkBytes;

      // 3) 当前库（另一份数据），用它恢复
      final current = PlainLeafDatabase.forTesting(openInMemoryDb());
      final service = CloudBackupService(
        backupService: BackupService(current),
        configStore: WebDavConfigStore(),
        httpClientFactory: _directClient,
      );

      final target = await service.restore(
        _config(server.url('/dav/')),
        const WebDavResource(name: 'cloud.plbk', path: '/dav/cloud.plbk'),
      );
      expect(target.existsSync(), isTrue);

      // 数据红线：恢复前自动备份过当前数据
      final safety = await BackupService(current).listBackups();
      expect(safety.any((b) => b.fileName.contains('before-restore')), isTrue);

      // 4) 用恢复后的库重新打开，校验数据真的回来了
      final reopened = PlainLeafDatabase.forTesting(NativeDatabase(target));
      addTearDown(reopened.close);
      final rows = await reopened.select(reopened.entries).get();
      expect(rows.any((row) => row.title == '云端恢复验收'), isTrue);
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('⑩ 下载到坏文件：中止恢复，不碰当前数据', () async {
    await withRealHttp(() async {
      final server = await FakeDavServer.start();
      addTearDown(server.close);
      server
        ..status = 200
        ..responseBody = utf8.encode('这不是备份包');

      final db = PlainLeafDatabase.forTesting(openInMemoryDb());
      addTearDown(db.close);
      final service = CloudBackupService(
        backupService: BackupService(db),
        configStore: WebDavConfigStore(),
        httpClientFactory: _directClient,
      );

      try {
        await service.restore(
          _config(server.url('/dav/')),
          const WebDavResource(name: 'broken.plbk', path: '/dav/broken.plbk'),
        );
        fail('应当因校验失败而中止');
      } on NetworkException catch (error) {
        expect(error.kind, NetworkErrorKind.protocol);
        // userMessage 按 kind 给通用文案（不暴露技术细节），具体原因记在 message 里
        expect(error.message, contains('备份包'));
      }

      // 关键：库还活着（没有被关掉替换）
      expect(await db.select(db.entries).get(), isNotNull);
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  // -------------------------------------------------------------- 凭据存储红线

  test('⑪ 凭据写入支持目录，且**不**随备份包外传（安全红线）', () async {
    final store = WebDavConfigStore();
    final config = _config(Uri.parse('https://dav.example.com/dav/backup/'));

    await store.write(config);
    expect(await store.read(), isNotNull);
    expect((await store.read())!.password, 'secret');

    // 导出备份包，断言包里既没有凭据文件、也没有任何含服务器地址的内容
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final plbk = await BackupService(db).exportBackup(fileName: 'secure.plbk');

    final archive = ZipDecoder().decodeBytes(plbk.readAsBytesSync());
    final names = archive.files.map((entry) => entry.name).toList();
    expect(names.any((name) => name.contains('webdav')), isFalse);
    expect(
      archive.files.any((entry) => entry.isFile &&
          utf8
              .decode(entry.content as List<int>, allowMalformed: true)
              .contains('dav.example.com')),
      isFalse,
      reason: '备份包里出现服务器地址，说明凭据被带出去了',
    );

    // 凭据文件确实落在支持目录根部
    final file = File(p.join(_root.path, WebDavConfigStore.fileName));
    expect(file.existsSync(), isTrue);

    await store.clear();
    expect(await store.read(), isNull);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('⑫ 配置校验：地址非法或账号为空时不通过', () {
    expect(_config(Uri.parse('https://dav.example.com/dav/')).isValid, isTrue);
    expect(
      const WebDavConfig(baseUrl: 'dav.example.com', username: 'a', password: 'b')
          .isValid,
      isFalse,
      reason: '缺少协议头',
    );
    expect(
      const WebDavConfig(
        baseUrl: 'https://dav.example.com/dav/',
        username: '',
        password: 'b',
      ).isValid,
      isFalse,
    );
  });

  // --------------------------------------------------------------------- UI

  testWidgets('⑬ 设置页渲染出云备份卡片与四个入口', (tester) async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);

    // 云备份卡片在「我的」页最下方，默认 800×600 视口下 ListView 根本不会
    // 把它 build 出来（离屏 ≠ offstage，find 再怎么设也找不到）。这里直接给一个
    // 足够高的视口，让整页一次性建完——比 scrollUntilVisible 稳定。
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: PlainLeafApp(
        themeMode: ThemeMode.light,
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, state) => const SettingsPage()),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('云备份（WebDAV）', skipOffstage: false), findsOneWidget);
    expect(find.text('配置', skipOffstage: false), findsOneWidget);
    expect(find.text('立即上传', skipOffstage: false), findsOneWidget);
    expect(find.text('从云端恢复', skipOffstage: false), findsOneWidget);

    // 未配置时，除「配置」外的按钮应当是不可点的
    final upload = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('立即上传', skipOffstage: false),
        matching: find.byType(FilledButton),
      ),
    );
    expect(upload.onPressed, isNull);
  });

  /// 写入门面用裸 ProviderContainer 测（不走 WidgetBinding）：
  /// 这里验证的是"调用 → 落盘 → 状态"这条链，挂 UI 只会引入 pumpAndSettle 的不确定性。
  test('⑭ 写入门面：保存后状态为成功且能读回；非法配置不写盘', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [dbProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final saved = await container.read(cloudBackupActionsProvider).saveConfig(
          _config(Uri.parse('https://dav.example.com/dav/')),
        );
    expect(saved, isTrue);
    expect(
      container.read(cloudBackupStatusProvider).kind,
      CloudBackupStatusKind.success,
    );
    // 配置已落盘，重新加载能读回
    expect(
      await container.read(cloudBackupServiceProvider).loadConfig(),
      isNotNull,
    );

    // 非法配置：不写盘，状态给可操作提示
    final rejected = await container.read(cloudBackupActionsProvider).saveConfig(
          const WebDavConfig(
            baseUrl: 'dav.example.com',
            username: 'a',
            password: 'b',
          ),
        );
    expect(rejected, isFalse);
    expect(
      container.read(cloudBackupStatusProvider).kind,
      CloudBackupStatusKind.failure,
    );
    // 上一次的合法配置没有被覆盖掉
    expect(
      (await container.read(cloudBackupServiceProvider).loadConfig())!.baseUrl,
      'https://dav.example.com/dav/',
    );
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
