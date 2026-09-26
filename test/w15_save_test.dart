import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:plainleaf/core/errors/app_exception.dart';
import 'package:plainleaf/core/media/image_saver.dart';
import 'package:plainleaf/features/gallery/domain/entities/gallery_asset.dart';
import 'package:plainleaf/features/gallery/presentation/photo_viewer_page.dart';
import 'package:plainleaf/features/gallery/presentation/providers/gallery_providers.dart';

/// W15 需求 3：把相册图片保存到设备
///
/// 分两层验：保存器本身（真实文件系统，桌面路径）与查看器按钮（注入假实现，
/// 不碰平台通道与真实磁盘）。
final Directory _root = Directory.systemTemp.createTempSync('plainleaf_w15save');

/// 1x1 透明 PNG：能真正被解码的最小合法图片，免得测试里出现"图片加载失败"
final List<int> _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePaths(_root.path);
  });

  group('保存器', () {
    test('① 桌面实现：原图内容完整复制到目标目录', () async {
      // 源目录与目标目录必须分开：产品里源在 App 私有目录、目标在下载目录。
      // 若放在同一目录，"重名加序号"会因为源文件本身占掉一个名字而失真。
      final source = File(p.join(_root.path, 'src', 'src.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(_pngBytes);

      final result = await const DesktopImageSaver().save(source.path);

      expect(result.outcome, SaveOutcome.directory);
      final saved = File(result.detail);
      expect(saved.existsSync(), isTrue);
      expect(saved.readAsBytesSync(), _pngBytes);
    });

    test('② 桌面实现：重名不覆盖，自动加序号', () async {
      final source = File(p.join(_root.path, 'src', 'dup.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(_pngBytes);

      final first = await const DesktopImageSaver().save(source.path);
      final second = await const DesktopImageSaver().save(source.path);

      expect(second.detail, isNot(first.detail));
      expect(p.basename(second.detail), 'dup-1.png');
      expect(File(first.detail).existsSync(), isTrue, reason: '先存的那份不能被顶掉');
    });

    test('③ 系统相册实现：宿主缺插件时给出可读的失败，而不是甩原始异常', () async {
      // flutter test 宿主没有注册 gal 插件，正好用来验证这条降级路径
      await expectLater(
        const GalleryImageSaver().save(p.join(_root.path, 'src.png')),
        throwsA(
          isA<ExportException>().having(
            (e) => e.message,
            'message',
            contains('不支持'),
          ),
        ),
      );
    });

    test('④ 假实现（测试用）只记录路径，不触磁盘', () async {
      final saver = RecordingImageSaver();
      await saver.save('/tmp/a.png');
      expect(saver.saved, ['/tmp/a.png']);
    });
  });

  group('查看器：保存按钮', () {
    testWidgets('⑤ 点「保存到设备」把**原图**路径交给保存器', (tester) async {
      const rel = 'media/2026/09/pic.png';
      final original = File(p.join(_root.path, rel))
        ..createSync(recursive: true)
        ..writeAsBytesSync(_pngBytes);

      final saver = RecordingImageSaver();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [imageSaverProvider.overrideWithValue(saver)],
          child: MaterialApp(
            home: PhotoViewerPage(
              assets: [
                GalleryAsset(
                  id: 1,
                  entryId: 1,
                  relPath: rel,
                  createdAt: DateTime(2026, 9, 26),
                ),
              ],
              initialIndex: 0,
              supportDir: _root.path,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('viewer-save')), findsOneWidget);
      await tester.tap(find.byKey(const Key('viewer-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(saver.saved, [original.path],
          reason: '必须保存原图，而不是 medium/thumb —— 缩略图是残次品');
    });
  });
}

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  /// 桌面保存走「下载」目录，测试里一并指向临时根
  @override
  Future<String?> getDownloadsPath() async => root;
}
