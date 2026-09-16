import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
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
      _controller = _controllerFromDelta(row.contentDelta);
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

  QuillController _controllerFromDelta(String deltaJson) {
    try {
      final decoded = jsonDecode(deltaJson);
      if (decoded is List && decoded.isNotEmpty) {
        return QuillController(
          document: Document.fromJson(decoded),
          selection: const TextSelection.collapsed(offset: 0),
        );
      }
    } on FormatException {
      // 旧数据/空数据：按空文档打开
    }
    return QuillController.basic();
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