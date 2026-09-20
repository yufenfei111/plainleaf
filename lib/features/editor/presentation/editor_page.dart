import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/debouncer.dart';
import '../../timeline/domain/entities/timeline_entry.dart';
import '../../timeline/domain/repositories/timeline_repository.dart';
import '../../timeline/presentation/providers/timeline_providers.dart';

/// 记录编辑器（W3 记录内核，issue #4/#5）
/// 路由：/editor（新建）或 /editor?id=N（编辑已有记录）
/// 自动保存：500ms 防抖（§5.2 规范）；保存状态常驻 AppBar 轻提示。
/// 新建流程：进入即以「草稿」落库（拿到稳定 id），此后每次防抖触发都走 updateEntry；
/// 退出时若标题与正文全空则回收进垃圾箱（不产生空记录），否则保留为草稿，
/// 由用户点「完成」显式发布（status=normal）。
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key, this.entryId});

  final int? entryId;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  QuillController? _controller;
  final _titleCtrl = TextEditingController();
  final _debouncer = Debouncer();

  late final TimelineRepository _repo = ref.read(timelineRepositoryProvider);

  final _picker = ImagePicker();
  List<_AttachedImage> _images = const [];

  int? _id;
  String _status = 'draft';
  bool _loading = true;
  bool _dirty = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (widget.entryId != null) {
      // 编辑已有记录：加载内容
      final row = await ref.read(dbProvider).entriesDao.findById(widget.entryId!);
      if (row == null) {
        if (mounted) context.pop();
        return;
      }
      _id = row.id;
      _status = row.status;
      _titleCtrl.text = row.title;
      // 兜底：历史数据与种子只有 plainText、contentDelta 为空，
      // 若不回填，正文会显示空白；更危险的是此时触发保存会把正文清空。
      _controller = _controllerFromDelta(
        row.contentDelta,
        fallbackText: row.plainText,
      );
      await _loadImages(row.id);
    } else {
      // 新建：先落一条草稿拿 id（保证防抖更新始终有稳定主键）
      _controller = QuillController.basic();
      _id = await _repo.saveEntry(const EntryDraft(
        title: '',
        plainText: '',
        status: EntryStatus.draft,
      ));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadImages(int entryId) async {
    final list = await ref.read(dbProvider).assetsDao.byEntry(entryId);
    if (!mounted) return;
    setState(() {
      _images = [
        for (final a in list) _AttachedImage(assetId: a.id, relPath: a.relPath),
      ];
    });
  }

  /// 拍照或选图 → 复制进私有目录 + assets 落库（W4，issue #7）
  Future<void> _pickAndAttach(ImageSource source) async {
    if (_id == null) return;
    final xFile = await _picker.pickImage(source: source, imageQuality: 90);
    if (xFile == null) return;
    try {
      final assetId = await ref
          .read(timelineRepositoryProvider)
          .attachImage(_id!, xFile.path);
      if (!mounted) return;
      setState(() {
        _images = [
          ..._images,
          _AttachedImage(assetId: assetId, localPath: xFile.path),
        ];
      });
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片挂接失败：$error')),
        );
      }
    }
  }

  Future<void> _detachImage(_AttachedImage img) async {
    await ref.read(dbProvider).assetsDao.softDelete(img.assetId);
    if (!mounted) return;
    setState(() => _images = _images.where((i) => i != img).toList());
  }

  /// Delta → 控制器；解析不出实质内容时用 [fallbackText] 回填。
  /// 兜底场景：种子数据、W3 之前落库的记录、以及任何只写了 plainText 的条目
  /// （contentDelta 为空串 → jsonDecode 抛 FormatException → 若直接给空文档，
  /// 用户点「完成」时 flush 保存就会把正文覆盖成空——属于数据丢失级缺陷）。
  QuillController _controllerFromDelta(
    String deltaJson, {
    String fallbackText = '',
  }) {
    try {
      final decoded = jsonDecode(deltaJson);
      if (decoded is List && decoded.isNotEmpty) {
        final doc = Document.fromJson(decoded);
        // Delta 能解析但内容为空（如只有换行）时同样回退
        if (doc.toPlainText().trim().isNotEmpty || fallbackText.trim().isEmpty) {
          return QuillController(
            document: doc,
            selection: const TextSelection.collapsed(offset: 0),
          );
        }
      }
    } on FormatException {
      // 空串 / 非法 JSON：落到下面的纯文本兜底
    }
    return _controllerFromPlainText(fallbackText);
  }

  QuillController _controllerFromPlainText(String text) {
    final doc = Document();
    if (text.isNotEmpty) doc.insert(0, text);
    return QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  String _deltaJson() => jsonEncode(_controller!.document.toDelta().toList());

  String _plainText() => _controller!.document.toPlainText().trim();

  bool get _isEmpty => _titleCtrl.text.trim().isEmpty && _plainText().isEmpty;

  void _onContentChanged() {
    if (_id == null) return;
    if (!_dirty) setState(() => _dirty = true);
    _debouncer(_persist);
  }

  Future<void> _persist() async {
    if (_id == null || _controller == null || _closed) return;
    final title = _titleCtrl.text.trim();
    final text = _plainText();
    try {
      await _repo.updateEntry(
        _id!,
        EntryDraft(
          title: title,
          plainText: text,
          status: _status == 'normal' ? EntryStatus.normal : EntryStatus.draft,
          contentDelta: _deltaJson(),
        ),
      );
      if (mounted && _dirty) setState(() => _dirty = false);
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('自动保存失败：$error')),
        );
      }
    }
  }

  /// 发布：状态转 normal，立即冲刷保存后返回时间轴
  Future<void> _publish() async {
    if (_id == null) return;
    _debouncer.flush(_persist);
    if (_status != 'normal') {
      await _repo.setStatus(_id!, status: 'normal');
      _status = 'normal';
    }
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _closed = true;
    _debouncer.dispose();
    _titleCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_loading || controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          // 返回时冲刷保存；空记录直接进回收站（数据红线：不留垃圾行）
          _debouncer.flush(_persist);
          if (_id != null && _isEmpty) {
            await _repo.softDelete(_id!);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_dirty ? '保存中…' : '已保存'),
          actions: [
            TextButton(
              onPressed: _isEmpty ? null : _publish,
              child: const Text('完成'),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _titleCtrl,
                onChanged: (_) => _onContentChanged(),
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(
                  hintText: '标题',
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(height: 1),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: QuillSimpleToolbar(
                controller: controller,
                config: const QuillSimpleToolbarConfig(
                  showDividers: false,
                  showFontFamily: false,
                  showFontSize: false,
                  showBoldButton: true,
                  showItalicButton: true,
                  showUnderLineButton: true,
                  showStrikeThrough: true,
                  showInlineCode: true,
                  showColorButton: false,
                  showBackgroundColorButton: false,
                  showClearFormat: true,
                  showAlignmentButtons: false,
                  showHeaderStyle: false,
                  showListNumbers: true,
                  showListBullets: true,
                  showListCheck: true,
                  showCodeBlock: true,
                  showQuote: true,
                  showIndent: true,
                  showLink: false,
                  showUndo: true,
                  showRedo: true,
                  showDirection: false,
                  showSearchButton: false,
                ),
              ),
            ),
            const Divider(height: 1),
            _ImageStrip(images: _images, onPick: _pickAndAttach, onRemove: _detachImage),
            const Divider(height: 1),
            Expanded(
              child: QuillEditor.basic(
                controller: controller,
                config: const QuillEditorConfig(
                  padding: EdgeInsets.all(16),
                  placeholder: '记点什么…',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 编辑器附件条上的图片视图
class _AttachedImage {
  const _AttachedImage({required this.assetId, this.relPath, this.localPath});

  final int assetId;
  final String? relPath;
  final String? localPath;
}

/// 图片附件条（W4 附件条模式，issue #7；quill 内嵌混排按深坑预案延后，W6 统一缩略图管线）
class _ImageStrip extends StatelessWidget {
  const _ImageStrip({
    required this.images,
    required this.onPick,
    required this.onRemove,
  });

  final List<_AttachedImage> images;
  final Future<void> Function(ImageSource source) onPick;
  final Future<void> Function(_AttachedImage image) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Row(
        children: [
          IconButton(
            tooltip: '拍照',
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: () => onPick(ImageSource.camera),
          ),
          IconButton(
            tooltip: '相册选图',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => onPick(ImageSource.gallery),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final img in images)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _ImageTile(image: img),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => onRemove(img),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.image});

  final _AttachedImage image;

  @override
  Widget build(BuildContext context) {
    final path = image.localPath ?? image.relPath;
    if (path == null) return const SizedBox(width: 72, height: 72);
    return Image.file(
      File(path),
      width: 72,
      height: 72,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const SizedBox(
        width: 72,
        height: 72,
        child: Icon(Icons.broken_image_outlined),
      ),
    );
  }
}
