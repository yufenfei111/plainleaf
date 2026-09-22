import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../shared/widgets/debouncer.dart';
import '../../notebooks/presentation/providers/notebooks_providers.dart';
import '../../timeline/domain/entities/timeline_entry.dart';
import '../../timeline/domain/repositories/timeline_repository.dart';
import '../../timeline/presentation/providers/timeline_providers.dart';

/// 记录编辑器（W3 记录内核，issue #4/#5；W10 补齐分类属性与图片修复）
/// 路由：/editor（新建）或 /editor?id=N（编辑已有记录）
/// 自动保存：500ms 防抖（§5.2 规范）；保存状态常驻 AppBar 轻提示。
/// 新建流程：进入即以「草稿」落库（拿到稳定 id），此后每次防抖触发都走 updateEntry；
/// 退出时若标题与正文全空则回收进垃圾箱（不产生空记录），否则保留为草稿，
/// 由用户点「完成」显式发布（status=normal）。
///
/// W10 修复的三类历史缺陷（都会在真机上表现为「图片异常/编辑异常」）：
/// ① 已有记录的附件图用**相对路径**直接 Image.file → 文件不存在 → 全部破图；
///    现统一「thumb 优先 + 支持目录拼接 + cacheWidth 限制解码」。
/// ② 新建记录时落草稿是异步的，id 未就绪期间的敲击被静默丢弃；
///    现先把输入标记为待存，id 就绪后立刻冲刷。
/// ③ dispose 只取消防抖不执行、发布时内容与状态两个事务并发；
///    现 dispose 先冲刷，发布 await 内容落库后再置 status。
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

  // 分类属性（W10）：此前编辑器无法设置类型/笔记本/心情，
  // 建出来的记录永远落在默认类型且不属于任何笔记本，事后再没法归类。
  EntryType _type = EntryType.note;
  int? _notebookId;
  int? _mood;
  String? _savedMetaSignature;

  /// id 尚未就绪时用户已经敲了字（新建首帧竞态），拿到 id 后补一次保存
  bool _pendingPersist = false;

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
      _type = EntryType.fromName(row.type);
      _notebookId = row.notebookId;
      _mood = row.mood;
      _savedMetaSignature = _metaSignature();
      await _loadImages(row.id);
    } else {
      // 新建：先落一条草稿拿 id（保证防抖更新始终有稳定主键）
      _controller = QuillController.basic();
      _savedMetaSignature = _metaSignature();
      _id = await _repo.saveEntry(EntryDraft(
        title: '',
        plainText: '',
        status: EntryStatus.draft,
        type: _type,
        notebookId: _notebookId,
        mood: _mood,
      ));
    }
    if (!mounted) return;
    setState(() => _loading = false);
    // 竞态兜底：草稿 id 返回前用户已经输入过，这里补一次保存，不能丢字。
    if (_pendingPersist) {
      _pendingPersist = false;
      unawaited(_persist());
    }
  }

  Future<void> _loadImages(int entryId) async {
    final list = await ref.read(dbProvider).assetsDao.byEntry(entryId);
    if (!mounted) return;
    setState(() {
      _images = [
        for (final a in list)
          _AttachedImage(
            assetId: a.id,
            relPath: a.relPath,
            thumbPath: a.thumbPath,
          ),
      ];
    });
  }

  /// 拍照或选图 → 复制进私有目录 + assets 落库（W4，issue #7）
  ///
  /// 挂接完成后重新从库里读一次列表：转码是在 attachImage 内部异步补齐的，
  /// 只有回读才能拿到 thumbPath——直接用选图时的临时路径，
  /// 一来是系统缓存目录（随时被清），二来会把数 MB 原图塞进 72dp 的格子。
  Future<void> _pickAndAttach(ImageSource source) async {
    if (_id == null) return;
    final xFile = await _picker.pickImage(source: source, imageQuality: 90);
    if (xFile == null) return;
    try {
      await ref
          .read(timelineRepositoryProvider)
          .attachImage(_id!, xFile.path);
      if (!mounted) return;
      await _loadImages(_id!);
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

  /// 分类属性指纹：与上次落库的值一致时跳过写库，避免每次防抖都多一个事务
  String _metaSignature() => '${_type.name}|${_notebookId ?? ''}|${_mood ?? ''}';

  void _onContentChanged() {
    if (!_dirty && mounted) setState(() => _dirty = true);
    if (_id == null) {
      // 新建：落草稿还在路上，先把「有待存内容」记下来，id 一到就冲刷。
      // 此前这里直接 return，用户在首帧敲的字会被静默吞掉。
      _pendingPersist = true;
      return;
    }
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
      await _writeMeta();
      if (mounted && _dirty) setState(() => _dirty = false);
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('自动保存失败：$error')),
        );
      }
    }
  }

  /// 写回分类属性（类型 / 笔记本 / 心情）；无变化则跳过
  Future<void> _writeMeta() async {
    final id = _id;
    if (id == null) return;
    final signature = _metaSignature();
    if (signature == _savedMetaSignature) return;
    await _repo.updateEntryMeta(
      id,
      type: _type,
      notebookId: _notebookId,
      clearNotebook: _notebookId == null,
      mood: _mood,
      clearMood: _mood == null,
    );
    _savedMetaSignature = signature;
  }

  /// 发布：先 await 内容落库，再置 status=normal（顺序反了会让两个事务抢锁，
  /// 且 FTS 可能停留在旧内容上），最后返回时间轴
  Future<void> _publish() async {
    if (_id == null) return;
    setState(() => _dirty = true);
    await _debouncer.flushAsync(_persist);
    if (!mounted) return;
    if (_status != 'normal') {
      await _repo.setStatus(_id!, status: 'normal');
      _status = 'normal';
    }
    if (mounted) context.pop();
  }

  Future<void> _onExit() async {
    await _debouncer.flushAsync(_persist);
    if (_id != null && _isEmpty) {
      await _repo.softDelete(_id!);
    }
  }

  @override
  void dispose() {
    // 先冲刷再关门：debouncer.dispose() 只取消不执行，
    // 页面被系统回收（不经过 PopScope）时会丢掉最后 500ms 的输入。
    _debouncer.flush(_persist);
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
    // 附件图的解析基准：顶层取一次往下传字符串（卡片内不再起异步）
    final root = ref.watch(supportDirProvider).valueOrNull;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          // 返回时冲刷保存；空记录直接进回收站（数据红线：不留垃圾行）
          await _onExit();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _SaveStatusLabel(dirty: _dirty),
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
            _MetaBar(
              type: _type,
              notebookId: _notebookId,
              mood: _mood,
              onTypeChanged: (t) => setState(() {
                _type = t;
                _onContentChanged();
              }),
              onNotebookChanged: (id) => setState(() {
                _notebookId = id;
                _onContentChanged();
              }),
              onMoodChanged: (m) => setState(() {
                _mood = m;
                _onContentChanged();
              }),
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
            _ImageStrip(
              images: _images,
              root: root,
              onPick: _pickAndAttach,
              onRemove: _detachImage,
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

/// AppBar 上的保存状态：只在「保存中/已保存」之间切换，用 AnimatedSwitcher 淡入淡出，
/// 避免文字硬切造成的闪烁（W10 交互打磨）
class _SaveStatusLabel extends StatelessWidget {
  const _SaveStatusLabel({required this.dirty});

  final bool dirty;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text(
        dirty ? '保存中…' : '已保存',
        key: ValueKey<bool>(dirty),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

/// 分类属性条（W10）：类型 / 笔记本 / 心情。
///
/// 之前这三项在编辑器里完全不可达——建出来的记录一律默认类型、不归属任何笔记本、
/// 心情为空，用户事后无从归类，只能重新创建。放在标题下方常驻，一行三个 chip。
class _MetaBar extends ConsumerWidget {
  const _MetaBar({
    required this.type,
    required this.notebookId,
    required this.mood,
    required this.onTypeChanged,
    required this.onNotebookChanged,
    required this.onMoodChanged,
  });

  final EntryType type;
  final int? notebookId;
  final int? mood;
  final ValueChanged<EntryType> onTypeChanged;
  final ValueChanged<int?> onNotebookChanged;
  final ValueChanged<int?> onMoodChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(notebooksStreamProvider);
    final name = notebooks.maybeWhen(
      data: (list) => list
          .where((n) => n.id == notebookId)
          .map((n) => n.name)
          .firstOrNull,
      orElse: () => null,
    );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _MenuChip<EntryType>(
            icon: Icons.label_outline,
            label: type.label,
            tooltip: '记录类型',
            entries: [
              for (final t in EntryType.values)
                PopupMenuItem<EntryType>(value: t, child: Text(t.label)),
            ],
            onSelected: onTypeChanged,
          ),
          const SizedBox(width: 8),
          _MenuChip<int?>(
            icon: Icons.book_outlined,
            label: name ?? '未归类',
            tooltip: '笔记本',
            entries: [
              const PopupMenuItem<int?>(value: null, child: Text('未归类')),
              ...notebooks.maybeWhen(
                data: (list) => [
                  for (final n in list)
                    PopupMenuItem<int?>(value: n.id, child: Text(n.name)),
                ],
                orElse: () => const <PopupMenuEntry<int?>>[],
              ),
            ],
            onSelected: onNotebookChanged,
          ),
          const SizedBox(width: 8),
          _MenuChip<int?>(
            icon: Icons.mood_outlined,
            label: mood == null ? '心情' : '心情 $mood',
            tooltip: '心情（1–5 档）',
            entries: [
              const PopupMenuItem<int?>(value: null, child: Text('不记录')),
              for (var i = 1; i <= 5; i++)
                PopupMenuItem<int?>(value: i, child: Text('$i 档')),
            ],
            onSelected: onMoodChanged,
          ),
        ],
      ),
    );
  }
}

/// 属性条上的下拉 chip（点击弹出菜单选择）
class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.icon,
    required this.label,
    required this.entries,
    required this.onSelected,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final List<PopupMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (_) => entries,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: cs.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

/// 编辑器附件条上的图片视图
class _AttachedImage {
  const _AttachedImage({
    required this.assetId,
    required this.relPath,
    this.thumbPath,
  });

  final int assetId;

  /// 原图相对路径（以 App 支持目录为基准）
  final String relPath;

  /// 缩略图相对路径（长边 400）；为空说明还没转码，回退原图但限制解码尺寸
  final String? thumbPath;
}

/// 图片附件条（W4 附件条模式，issue #7；quill 内嵌混排按深坑预案延后，W6 统一缩略图管线）
class _ImageStrip extends StatelessWidget {
  const _ImageStrip({
    required this.images,
    required this.onPick,
    required this.onRemove,
    this.root,
  });

  final List<_AttachedImage> images;
  final Future<void> Function(ImageSource source) onPick;
  final Future<void> Function(_AttachedImage image) onRemove;

  /// App 支持目录（相对路径的解析基准）；null 时图片位显示占位
  final String? root;

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
                          child: _ImageTile(image: img, root: root),
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

/// 附件图缩略图（W10 修复）
///
/// 两处必须同时做到，缺一个就会「要么破图、要么卡」：
/// 1. 相对路径要拼上支持目录——库里存的是 `media/yyyy/mm/xxx.jpg`，
///    直接 Image.file 必然 FileNotFound，表现为全部破图；
/// 2. 优先 thumb 且限制 cacheWidth——72dp 的格子里解码 4000px 原图，
///    单张就吃掉几十 MB 解码内存，多图时会明显的卡顿与内存尖峰。
class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.image, this.root});

  final _AttachedImage image;
  final String? root;

  static const double size = 72;

  @override
  Widget build(BuildContext context) {
    final base = root;
    if (base == null) {
      return const SizedBox(width: size, height: size);
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.file(
      File(p.join(base, image.thumbPath ?? image.relPath)),
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * dpr).round(),
      errorBuilder: (context, error, stackTrace) => const SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.broken_image_outlined),
      ),
    );
  }
}
