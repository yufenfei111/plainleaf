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
import '../../../core/errors/app_exception.dart';
import '../../../core/media/asset_kind.dart';
import '../../../core/media/attachment_picker.dart';
import '../../../shared/widgets/debouncer.dart';
import '../../notebooks/presentation/providers/notebooks_providers.dart';
import '../../timeline/domain/entities/timeline_entry.dart';
import '../../timeline/domain/repositories/timeline_repository.dart';
import '../../timeline/presentation/providers/timeline_providers.dart';
import 'providers/editor_providers.dart';

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
///
/// W11 打磨（轻量、克制，不堆视觉装饰）：
/// ① 底部字数统计：正文去空白字符数，走 ValueNotifier 局部刷新——
///    不用 setState，否则每敲一个字都要重建整棵 QuillEditor；
/// ② 退出二次确认：仅「有内容且未落库」时拦一次；
/// ③ 附件图长按看大图：medium 优先 + 按屏幕宽×DPR 限制 cacheWidth，不做缩放手势。
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key, this.entryId});

  final int? entryId;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

/// 正文字数：去空白后按「字符」计（中英文同权）。
///
/// 抽成纯函数是为了可单测——Widget 用例里数 quill 的字符既慢又脆；
/// 空白（含 quill 每行末尾的换行）不计入，否则「敲 10 个回车」也算 10 字。
/// 用 runes 而不是 String.length：后者按 UTF-16 码元计，一个非 BMP 字符会算成 2。
int countBodyChars(String plainText) {
  if (plainText.isEmpty) return 0;
  return plainText.replaceAll(_bodyWhitespace, '').runes.length;
}

final RegExp _bodyWhitespace = RegExp(r'\s+');

/// 全屏大图的解码宽度上限：屏幕宽 × 设备像素比。
///
/// 手机原图动辄 4000px 数 MB，全屏解码不加限制会直接顶出内存尖峰；
/// 夹在 [1, 4096] 是为了挡住「测量值为 0」与「超高 DPR」两种极端输入。
int fullscreenCacheWidth(double screenWidth, double devicePixelRatio) =>
    (screenWidth * devicePixelRatio).round().clamp(1, 4096).toInt();

/// 全屏大图首选来源：medium（长边 1600）优先，缺失时回退原图。
/// 与详情页同一口径，避免两处对「该解码哪张」给出不同答案。
String viewerRelPath(String relPath, String? mediumPath) =>
    mediumPath ?? relPath;

/// 是否拦截退出：**有内容** 且 **有未落库的改动** 且 **不是程序主动退出**。
///
/// 三条缺一不可：空记录退出时会被回收（不该拿对话框拦一下）；
/// 已落库的内容再拦就是打扰；点「完成」发布、或用户已在对话框里确认过，
/// 都属于程序主动退出，必须直接放行——否则发布流程会被自己挡死。
bool shouldConfirmExit({
  required bool dirty,
  required bool empty,
  required bool bypass,
}) =>
    dirty && !empty && !bypass;

class _EditorPageState extends ConsumerState<EditorPage> {
  QuillController? _controller;
  final _titleCtrl = TextEditingController();
  final _debouncer = Debouncer();

  // 不要写成 late final + 惰性取值：dispose() 里会冲刷最后一次保存，
  // 那时 ref 已失效，惰性初始化会走到 ref.read 抛 StateError
  // （「Cannot use ref after the widget was disposed」）。放在 initState 里提前取到手。
  late TimelineRepository _repo;

  final _picker = ImagePicker();
  List<_AttachedAsset> _attachments = const [];

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

  /// 正文字数（去空白）：交给字数条自己监听，
  /// 这样每敲一个字只重建那一行小字，不必重建整棵 QuillEditor
  final ValueNotifier<int> _bodyChars = ValueNotifier<int>(0);

  /// 正文变更订阅：quill 的 Document.changes 只在文档真被改动时发事件，
  /// 不像 controller.addListener 那样连移动光标也会触发（会导致无意义的写库）
  StreamSubscription<DocChange>? _docSub;

  /// 程序主动退出（点「完成」发布、或用户已在确认框里选了退出）：
  /// 下一次 pop 必须直接放行，否则发布流程会被自己的 PopScope 挡死
  bool _bypassExitConfirm = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(timelineRepositoryProvider);
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
      await _loadAttachments(row.id);
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
    // 绑定正文变更 + 首帧字数都放在 setState 之前：
    // 首帧就带上正确字数，省掉一次「0 字 → N 字」的跳变
    _bindDocumentChanges();
    _refreshBodyChars();
    setState(() => _loading = false);
    // 竞态兜底：草稿 id 返回前用户已经输入过，这里补一次保存，不能丢字。
    if (_pendingPersist) {
      _pendingPersist = false;
      unawaited(_persist());
    }
  }

  /// 回读附件列表 —— **不限类型**（W17 起附件条要显示图片之外的文件）
  Future<void> _loadAttachments(int entryId) async {
    final list = await ref.read(dbProvider).assetsDao.allByEntry(entryId);
    if (!mounted) return;
    setState(() {
      _attachments = [
        for (final a in list)
          _AttachedAsset(
            assetId: a.id,
            relPath: a.relPath,
            kind: AssetKind.fromStorage(a.kind),
            thumbPath: a.thumbPath,
            mediumPath: a.mediumPath,
            originalName: a.originalName,
            sizeBytes: a.sizeBytes,
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
      await _loadAttachments(_id!);
    } on Exception catch (error) {
      if (mounted) _toast('图片挂接失败：$error');
    }
  }

  /// 选任意类型的本机文件 → 原样挂接（W17 多格式）
  ///
  /// 与选图**分开**是刻意的：选图仍走 `image_picker`（带 imageQuality 压缩、
  /// 直接对接系统相册），而"选文件"要的是原样导入 —— 不压缩、不改格式。
  Future<void> _pickAndAttachFile() async {
    if (_id == null) return;
    final PickedAttachment? picked;
    try {
      picked = await ref.read(attachmentPickerProvider).pickFile();
    } on PickerException catch (error) {
      if (mounted) _toast(error.message);
      return;
    }
    // 用户取消是正常操作，不提示、不落库
    if (picked == null) return;
    try {
      await ref.read(timelineRepositoryProvider).attachFile(_id!, picked.path);
      if (!mounted) return;
      await _loadAttachments(_id!);
    } on Exception catch (error) {
      if (mounted) _toast('文件挂接失败：$error');
    }
  }

  /// 打开附件（W17 P0-6）：图片走内置全屏，其余交给系统应用。
  Future<void> _openAttachment(_AttachedAsset asset, String root) async {
    if (asset.hasBitmap) {
      _openFullscreen(context, asset, root);
      return;
    }
    try {
      await ref.read(fileOpenerProvider).open(p.join(root, asset.relPath));
    } on Exception catch (error) {
      if (mounted) _toast('$error');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _detach(_AttachedAsset asset) async {
    await ref.read(dbProvider).assetsDao.softDelete(asset.assetId);
    if (!mounted) return;
    setState(
        () => _attachments = _attachments.where((a) => a != asset).toList());
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

  /// 订阅正文变更（字数 + 防抖保存）；重复调用时先退订旧的
  void _bindDocumentChanges() {
    _docSub?.cancel();
    final controller = _controller;
    if (controller == null) return;
    _docSub = controller.document.changes.listen((_) => _onContentChanged());
  }

  void _refreshBodyChars() {
    final controller = _controller;
    if (controller == null) return;
    _bodyChars.value = countBodyChars(controller.document.toPlainText());
  }

  void _onContentChanged() {
    _refreshBodyChars();
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
    // 发布是显式退出：置位后再 pop，避免被「未保存」确认框拦住
    _bypassExitConfirm = true;
    if (mounted) context.pop();
  }

  /// 被拦截的退出：给一次确认。
  ///
  /// 收尾只用对话框自己的 context（W10 坑：用页面级 context 会把整页弹掉）；
  /// 确认退出后先 setState 置位再 pop——PopScope.canPop 是在 didUpdateWidget 里
  /// 同步给 canPopNotifier 的，不重建就还是旧值，pop 会被再拦一次。
  Future<void> _handleExitConfirm() async {
    final navigator = Navigator.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('保留草稿并退出？'),
        content: const Text('还有改动没写完。退出后内容会留在草稿箱里，随时可以接着写。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('保留草稿并退出'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    setState(() => _bypassExitConfirm = true);
    // 等下一帧（此时 PopScope 已用新的 canPop 重建）再真正 pop；
    // pop 成功后 onPopInvokedWithResult 的 didPop 分支会冲刷保存
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) navigator.pop();
    });
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
    _docSub?.cancel();
    _bodyChars.dispose();
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
      // 只在「有内容且未落库」时拦；空记录与已保存的情况一律直接放行
      canPop: !shouldConfirmExit(
        dirty: _dirty,
        empty: _isEmpty,
        bypass: _bypassExitConfirm,
      ),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          // 返回时冲刷保存；空记录直接进回收站（数据红线：不留垃圾行）
          await _onExit();
          return;
        }
        // 没 pop 成 = 被上面拦住了：给一次确认
        await _handleExitConfirm();
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
            _AttachmentStrip(
              assets: _attachments,
              root: root,
              onPickImage: _pickAndAttach,
              onPickFile: _pickAndAttachFile,
              onOpen: _openAttachment,
              onRemove: _detach,
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
            // 字数放在正文区底部：AppBar 已经放了保存态与「完成」，再挤会打架
            _CharCountBar(count: _bodyChars),
          ],
        ),
      ),
    );
  }
}

/// 底部字数条：只监听 [count]，整页不重建。
///
/// 用 AnimatedSwitcher 做 200ms 淡入淡出（不做数字滚动动画——那属于「看着热闹、
/// 读起来更慢」的装饰）。字数属于参考信息，故用 onSurfaceVariant 的低强调色。
class _CharCountBar extends StatelessWidget {
  const _CharCountBar({required this.count});

  final ValueNotifier<int> count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ValueListenableBuilder<int>(
        valueListenable: count,
        builder: (context, value, _) => Align(
          alignment: Alignment.centerLeft,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              '$value 字',
              key: ValueKey<int>(value),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
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

/// 编辑器附件条上的一个附件（W17 起不限类型，不再只有图片）
class _AttachedAsset {
  const _AttachedAsset({
    required this.assetId,
    required this.relPath,
    required this.kind,
    this.thumbPath,
    this.mediumPath,
    this.originalName,
    this.sizeBytes,
  });

  final int assetId;

  /// 原文件相对路径（以 App 支持目录为基准）
  final String relPath;

  /// 附件类型，决定怎么渲染：图片给缩略图，其余给类型图标
  final AssetKind kind;

  /// 缩略图相对路径（长边 400）。为空有两种含义：图片尚未转码，或本类型
  /// 本就不生成缩略图（非图片）—— 后者是常态，UI 必须自带图标兜底。
  final String? thumbPath;

  /// 中号图相对路径（长边 1600）；全屏查看的首选来源（仅图片有意义）
  final String? mediumPath;

  /// 原始文件名。落盘名是 uuid，**非图片文件必须显示它**，否则只剩一串 uuid
  final String? originalName;

  /// 文件大小（字节）；取不到为 null
  final int? sizeBytes;

  /// 是否可以显示位图（只有图片有缩略图/原图可显示）
  bool get hasBitmap => kind == AssetKind.image;

  /// 列表上显示的名字：优先原名，回退到落盘文件名
  String get displayName => originalName ?? p.basename(relPath);
}

/// 附件条（W4 附件条模式，issue #7；W17 起不限类型）
///
/// 左侧三个入口：拍照 / 相册选图 / **选择文件**。
/// 前两个走 `image_picker`（带压缩、直接对接系统相册），第三个走文件选择器
/// 原样导入 —— 语义不同，不合并成一个按钮。
class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({
    required this.assets,
    required this.onPickImage,
    required this.onPickFile,
    required this.onOpen,
    required this.onRemove,
    this.root,
  });

  final List<_AttachedAsset> assets;
  final Future<void> Function(ImageSource source) onPickImage;
  final Future<void> Function() onPickFile;
  final Future<void> Function(_AttachedAsset asset, String root) onOpen;
  final Future<void> Function(_AttachedAsset asset) onRemove;

  /// App 支持目录（相对路径的解析基准）；null 时格子只显示占位
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
            onPressed: () => onPickImage(ImageSource.camera),
          ),
          IconButton(
            tooltip: '相册选图',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => onPickImage(ImageSource.gallery),
          ),
          IconButton(
            tooltip: '选择文件（任意类型）',
            icon: const Icon(Icons.attach_file),
            onPressed: () => onPickFile(),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final asset in assets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _AttachmentTile(
                            asset: asset,
                            root: root,
                            onOpen: onOpen,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => onRemove(asset),
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

/// 附件格子（W17 起按类型分派）
///
/// **图片**走原来的缩略图路径。两处必须同时做到，缺一个就会「要么破图、要么卡」：
///   ① 相对路径要拼上支持目录 —— 库里存的是 `media/yyyy/mm/xxx.jpg`，
///      直接 `Image.file` 必然 FileNotFound，表现为全部破图；
///   ② 优先 thumb 且限制 `cacheWidth` —— 72dp 的格子里解码 4000px 原图，
///      单张就吃掉几十 MB 解码内存，多图时会明显卡顿。
///
/// **其他类型**给类型图标 + 扩展名。注意**不要试图用 Image.file 渲染 PDF**，
/// 那只会得到一堆破图占位，比直接显示图标更糟。
/// 图片"刚挂上还没转码"时也落到图标分支，正好充当转码前的占位。
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.asset,
    required this.onOpen,
    this.root,
  });

  final _AttachedAsset asset;
  final Future<void> Function(_AttachedAsset asset, String root) onOpen;
  final String? root;

  static const double size = 72;

  @override
  Widget build(BuildContext context) {
    final base = root;
    final scheme = Theme.of(context).colorScheme;
    final bitmapRel = asset.thumbPath ?? asset.relPath;
    final canShowBitmap =
        base != null && asset.hasBitmap && bitmapRel.isNotEmpty;

    return GestureDetector(
      // 点开：图片进内置全屏，其余交给系统应用（见 EditorPage._openAttachment）
      onTap: base == null ? null : () => onOpen(asset, base),
      child: canShowBitmap
          ? Image.file(
              File(p.join(base, bitmapRel)),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth:
                  (size * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (context, error, stackTrace) =>
                  _FileBadge(asset: asset, scheme: scheme),
            )
          : _FileBadge(asset: asset, scheme: scheme),
    );
  }
}

/// 非图片附件（以及尚未转码的图片）的格子：类型图标 + 扩展名
///
/// 这里显示扩展名而不是完整文件名：72dp 放不下「作业第三章.pdf」，
/// 截断成半截名字反而更难看。完整名字留给点开后的动作与详情页。
class _FileBadge extends StatelessWidget {
  const _FileBadge({required this.asset, required this.scheme});

  final _AttachedAsset asset;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(asset.relPath).replaceFirst('.', '').toUpperCase();
    return Container(
      width: _AttachmentTile.size,
      height: _AttachmentTile.size,
      color: scheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_iconFor(asset.kind), size: 24, color: scheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              ext.isEmpty ? '文件' : ext,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(AssetKind kind) => switch (kind) {
        AssetKind.image => Icons.image_outlined,
        AssetKind.video => Icons.movie_outlined,
        AssetKind.audio => Icons.audiotrack_outlined,
        AssetKind.pdf => Icons.picture_as_pdf_outlined,
        AssetKind.document => Icons.description_outlined,
        AssetKind.archive => Icons.folder_zip_outlined,
        AssetKind.other => Icons.insert_drive_file_outlined,
      };
}

/// 全屏看大图：medium 优先 + 按屏幕宽×DPR 限制 cacheWidth（与详情页同一口径）。
///
/// 没有 InteractiveViewer：这里只做「看大图」，点任意处或右上角关闭；
/// 收尾统一用对话框自己的 context（页面级 context.pop() 会把整页弹掉）。
void _openFullscreen(
  BuildContext context,
  _AttachedAsset asset,
  String root,
) {
  final cacheWidth = fullscreenCacheWidth(
    MediaQuery.sizeOf(context).width,
    MediaQuery.devicePixelRatioOf(context),
  );
  final cs = Theme.of(context).colorScheme;
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog.fullscreen(
      child: GestureDetector(
        onTap: () => Navigator.of(dialogCtx).pop(),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.file(
                File(p.join(root, viewerRelPath(asset.relPath, asset.mediumPath))),
                cacheWidth: cacheWidth,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(dialogCtx).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
