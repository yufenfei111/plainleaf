import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../errors/app_exception.dart';

/// WebDAV 上的一项资源（PROPFIND 列目录的结果）
///
/// 只保留备份需要的四个字段：名字、路径、修改时间、大小。
/// 不解析 etag / contenttype 等——单向备份用不到，多解析一个字段就多一处格式兼容风险。
class WebDavResource {
  const WebDavResource({
    required this.name,
    required this.path,
    this.modifiedAt,
    this.sizeBytes,
    this.isDirectory = false,
  });

  /// 文件名（含扩展名），目录为最后一段目录名
  final String name;

  /// 服务器上的路径（以 / 开头，已解码）
  final String path;

  /// 最后修改时间（服务器未提供时为 null）
  final DateTime? modifiedAt;

  /// 字节数（服务器未提供时为 null）
  final int? sizeBytes;

  final bool isDirectory;

  /// 是否为 .plbk 备份包（列目录后 UI 只关心这个）
  bool get isBackupPackage => !isDirectory && name.toLowerCase().endsWith('.plbk');
}

/// 一次原始 HTTP 交互的结果（内部用）
class _Response {
  const _Response(this.statusCode, this.bytes);

  final int statusCode;
  final List<int> bytes;
}

/// WebDAV 单向备份客户端（W13）
///
/// **为什么用 `dart:io` 的 HttpClient 而不引 `http`/`dio`**：
/// 备份只需要 PUT / GET / PROPFIND / MKCOL 四个动词，dart:io 原生就够；
/// 本轮明确不新增依赖（见 docs/w13-lessons.md S3），避免为一个小功能牵动 pubspec。
///
/// **只做单向**：上传本地备份包、拉回备份包、列目录。
/// 不做双向 LWW 同步（路线图已移出 v1.0），因此**没有**任何冲突合并逻辑。
///
/// 所有失败统一抛 [NetworkException] 并带上 [NetworkErrorKind]，UI 展示
/// [NetworkException.userMessage]，不展示原始异常。
class WebDavClient {
  WebDavClient({
    required Uri baseUrl,
    required String username,
    required String password,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : _base = baseUrl,
        _auth = base64Encode(utf8.encode('$username:$password')),
        _client = httpClient ?? HttpClient();

  final Uri _base;
  final String _auth;
  final HttpClient _client;

  /// 连接 / 等待响应 / 读取响应共用的超时。
  /// 必须显式设置：不设的话弱网下一次请求能把整个界面挂住。
  final Duration timeout;

  /// 释放底层连接（用完后必须调用，否则 socket 会挂到超时）
  void close() {
    _client.close(force: true);
  }

  /// 测试连接：对备份目录做一次 Depth 0 的 PROPFIND，2xx 即视为可用
  Future<void> ping() async {
    final response = await _send('PROPFIND', '', headers: const {'Depth': '0'});
    _throwIfFailed(response.statusCode, '连接测试');
  }

  /// 创建备份目录（已存在时服务器返回 405，按成功处理）
  Future<void> ensureDirectory() async {
    final response = await _send('MKCOL', '');
    if (response.statusCode == 405) return;
    _throwIfFailed(response.statusCode, '创建目录');
  }

  /// 列出备份目录下的资源，按修改时间倒序（最新在前）
  Future<List<WebDavResource>> listDirectory() async {
    final response = await _send('PROPFIND', '', headers: const {'Depth': '1'});
    final code = response.statusCode;
    if (code != 207 && code != 200) {
      // 401/404/5xx 给出可操作分类；其余 2xx（如 204）说明不是 WebDAV 目录
      _throwIfFailed(code, '列目录');
      throw NetworkException(
        '列目录失败：服务器未返回 WebDAV 目录列表（HTTP $code）',
        kind: NetworkErrorKind.protocol,
        statusCode: code,
      );
    }
    final body = utf8.decode(response.bytes, allowMalformed: true);
    final items = parsePropfind(body, _basePath());
    items.sort((a, b) {
      final at = a.modifiedAt;
      final bt = b.modifiedAt;
      if (at == null && bt == null) return a.name.compareTo(b.name);
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return items;
  }

  /// 上传（覆盖式写入）。[remoteName] 只取文件名，落到备份目录下。
  Future<void> putFile(String remoteName, List<int> bytes) async {
    final response = await _send(
      'PUT',
      remoteName,
      body: bytes,
      headers: const {'Content-Type': 'application/octet-stream'},
    );
    _throwIfFailed(response.statusCode, '上传');
  }

  /// 下载备份包，返回原始字节
  Future<List<int>> getFile(String remoteName) async {
    final response = await _send('GET', remoteName);
    _throwIfFailed(response.statusCode, '下载');
    return response.bytes;
  }

  // ---------------------------------------------------------------- 内部实现

  Future<_Response> _send(
    String method,
    String remotePath, {
    List<int>? body,
    Map<String, String>? headers,
  }) async {
    final uri = _resolve(remotePath);
    HttpClientRequest request;
    try {
      request = await _client.openUrl(method, uri).timeout(
            timeout,
            onTimeout: () => throw const NetworkException(
              '连接服务器超时',
              kind: NetworkErrorKind.timeout,
            ),
          );
    } on NetworkException {
      rethrow;
    } on Object catch (error) {
      throw _wrap(error);
    }

    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Basic $_auth')
      ..set(HttpHeaders.userAgentHeader, 'PlainLeaf');
    if (headers != null) {
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
    }
    if (body != null) request.add(body);

    try {
      final response = await request.close().timeout(
            timeout,
            onTimeout: () => throw const NetworkException(
              '等待服务器响应超时',
              kind: NetworkErrorKind.timeout,
            ),
          );
      final bytes = await _readAll(response);
      return _Response(response.statusCode, bytes);
    } on NetworkException {
      rethrow;
    } on Object catch (error) {
      throw _wrap(error);
    }
  }

  Future<List<int>> _readAll(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await response
        .timeout(
          timeout,
          onTimeout: (sink) => sink.addError(
            const NetworkException(
              '读取响应超时',
              kind: NetworkErrorKind.timeout,
            ),
          ),
        )
        .forEach(builder.add);
    return builder.takeBytes();
  }

  /// 把相对名拼到备份目录下。
  ///
  /// 目录路径统一补尾斜杠后再拼：直接用 `Uri.resolve` 会在 base 无尾斜杠时
  /// 把最后一段目录名吃掉（`/dav/backup` + `a.plbk` → `/dav/a.plbk`）。
  Uri _resolve(String remotePath) {
    final basePath = _base.path.endsWith('/') ? _base.path : '${_base.path}/';
    final rel = remotePath.startsWith('/') ? remotePath.substring(1) : remotePath;
    return Uri(
      scheme: _base.scheme,
      host: _base.host,
      port: _base.hasPort ? _base.port : null,
      path: '$basePath$rel',
    );
  }

  String _basePath() {
    final path = _base.path;
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  void _throwIfFailed(int statusCode, String action) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw _statusException(statusCode, action);
  }

  NetworkException _statusException(int code, String action) => NetworkException(
        '$action失败：HTTP $code',
        kind: switch (code) {
          401 || 403 => NetworkErrorKind.unauthorized,
          404 => NetworkErrorKind.notFound,
          >= 500 => NetworkErrorKind.server,
          _ => NetworkErrorKind.protocol,
        },
        statusCode: code,
      );

  /// 把底层异常映射成 [NetworkException]。
  ///
  /// 证书不受信/握手失败也算 offline：对用户来说「连不上」和「证书不对」
  /// 都是「这个地址不能用」，提示都指向检查地址与网络。
  NetworkException _wrap(Object error) {
    if (error is NetworkException) return error;
    if (error is SocketException ||
        error is TlsException ||
        error is HandshakeException ||
        error is HttpException) {
      return NetworkException(
        '网络不可用：$error',
        kind: NetworkErrorKind.offline,
        cause: error,
      );
    }
    return NetworkException('请求失败：$error', cause: error);
  }

  // ------------------------------------------------------- PROPFIND XML 解析

  /// `<response>` 块。命名空间前缀可能是 `d:` / `D:` / 无，统一容忍。
  static final RegExp _responseBlock = RegExp(
    r'<(?:\w+:)?response\b[^>]*>(.*?)</(?:\w+:)?response>',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _hrefTag = RegExp(
    r'<(?:\w+:)?href\b[^>]*>(.*?)</(?:\w+:)?href>',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _collectionTag = RegExp(
    r'<(?:\w+:)?collection\b[^>]*/?>',
    caseSensitive: false,
  );

  static final RegExp _lastModifiedTag = RegExp(
    r'<(?:\w+:)?getlastmodified\b[^>]*>(.*?)</(?:\w+:)?getlastmodified>',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _contentLengthTag = RegExp(
    r'<(?:\w+:)?getcontentlength\b[^>]*>(.*?)</(?:\w+:)?getcontentlength>',
    caseSensitive: false,
    dotAll: true,
  );

  /// 解析 PROPFIND 的 207 Multi-Status 响应（纯函数，便于单测）
  ///
  /// **为什么用正则而不是 XML 解析器**：只取 href / collection /
  /// getlastmodified / getcontentlength 四个字段，且这类响应由服务器程序生成、
  /// 格式稳定；为它引一个 XML 依赖不划算（本轮零新增依赖）。
  /// 代价是遇到极端畸形响应会漏项——用 [modifiedAt] 为 null 兜底，不抛异常。
  ///
  /// [dirPath] 用于剔除「目录自身」那一条（PROPFIND Depth 1 会把它一起返回）。
  static List<WebDavResource> parsePropfind(String xml, String dirPath) {
    final out = <WebDavResource>[];
    for (final block in _responseBlock.allMatches(xml)) {
      final content = block.group(1);
      if (content == null) continue;
      final hrefMatch = _hrefTag.firstMatch(content);
      if (hrefMatch == null) continue;
      final href = _decode(hrefMatch.group(1)!.trim());

      var path = href;
      // 部分服务器返回完整绝对 URL，统一收敛成路径
      if (path.startsWith('http://') || path.startsWith('https://')) {
        path = Uri.tryParse(path)?.path ?? path;
      }
      if (path.isEmpty) continue;

      final isDirectory = path.endsWith('/') || _collectionTag.hasMatch(content);
      final trimmed = isDirectory && path.endsWith('/')
          ? path.substring(0, path.length - 1)
          : path;
      if (_samePath(trimmed, dirPath)) continue;

      final segments = trimmed.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) continue;

      final rawModified = _capture(content, _lastModifiedTag);
      final rawLength = _capture(content, _contentLengthTag);

      out.add(WebDavResource(
        name: segments.last,
        path: trimmed,
        modifiedAt: rawModified == null ? null : _parseDate(rawModified),
        sizeBytes: rawLength == null ? null : int.tryParse(rawLength.trim()),
        isDirectory: isDirectory,
      ));
    }
    return out;
  }

  static String? _capture(String content, RegExp tag) {
    final match = tag.firstMatch(content);
    if (match == null) return null;
    final value = match.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static DateTime? _parseDate(String raw) {
    try {
      return HttpDate.parse(raw);
    } on Object {
      return null;
    }
  }

  /// 解码百分号转义；失败就退回原串（畸形转义不该让整个列表解析失败）
  static String _decode(String raw) {
    try {
      return Uri.decodeFull(raw);
    } on Object {
      return raw;
    }
  }

  /// 路径比较：忽略尾斜杠与末尾重复斜杠
  static bool _samePath(String a, String b) {
    String norm(String v) {
      var s = v;
      while (s.length > 1 && s.endsWith('/')) {
        s = s.substring(0, s.length - 1);
      }
      return s;
    }

    return norm(a) == norm(b);
  }
}
