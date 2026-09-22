import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../timeline/domain/entities/entry_asset.dart';
import '../../timeline/domain/entities/timeline_entry.dart';
import '../../timeline/presentation/providers/timeline_providers.dart';
import './providers/entry_detail_providers.dart';

/// 记录详情页（W8）
///
/// 路由约定（主代理稍后注册）：`/detail?id=N`，构造签名固定为
/// `EntryDetailPage({super.key, required this.entryId})`，改了接不上路由。
///
/// 性能红线：medium 是详情页大图的唯一正确来源（W6 两级缩略图管线的首个、
/// 也是唯一消费点）。列表/网格之外，手机原图动辄 4000px 数 MB，单张解码就会
/// 造成明显卡顿与内存尖峰——哪怕只显示一张，也绝不直接解码原图 relPath。
class EntryDetailPage extends ConsumerWidget {
  const EntryDetailPage({super.key, required this.entryId});

  final int entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 三路异步：记录详情、图片资产、支持目录（相对路径的解析基准）。
    // supportDir 顶层取一次往下传，避免每个图片位各自起 FutureBuilder 反复解析。
    final detail = ref.watch(entryDetailProvider(entryId));
    final assets = ref.watch(entryAssetsProvider(entryId));
    final supportDir = ref.watch(supportDirProvider);

    return Scaffold(
      appBar: AppBar(
        // 标题取 entry.title；空标题显示「无标题」，未加载/不存在时给中性占位。
        title: detail.maybeWhen(
          data: (entry) => Row(
            children: [
              if (entry != null && entry.pinned) ...[
                Icon(Icons.push_pin,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  entry == null
                      ? '记录详情'
                      : (entry.title.isEmpty ? '无标题' : entry.title),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          orElse: () => const Text('记录详情'),
        ),
        actions: [
          // 只在记录真实存在时暴露编辑/删除入口；否则菜单无意义。
          detail.maybeWhen(
            data: (entry) => entry == null
                ? const SizedBox.shrink()
                : PopupMenuButton<String>(
                    onSelected: (action) =>
                        _onMenuSelected(context, ref, action, entry),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(error: '$error'),
        data: (entry) {
          if (entry == null) {
            // 明确告知，而不是空白——id 不存在或记录已物理删除都会走到这里。
            return const _NotFoundView();
          }
          return _DetailBody(entry: entry, assets: assets, supportDir: supportDir);
        },
      ),
    );
  }

  /// 溢出菜单：编辑走编辑器路由，删除走写操作门面（错误三层透传第三层转 SnackBar）。
  Future<void> _onMenuSelected(
    BuildContext context,
    WidgetRef ref,
    String action,
    TimelineEntry entry,
  ) async {
    if (action == 'edit') {
      // 复用全局编辑器路由；编辑器未在本页实现，交给主代理的路由注册。
      context.push('/editor?id=$entryId');
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('移到回收站'),
          content: const Text('确定要把这条记录移到回收站吗？回收站里可恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await ref.read(timelineActionsProvider).softDelete(entry.id);
        if (!context.mounted) return;
        // 删除成功返回上一页（记录已从列表消失）。
        Navigator.of(context).pop();
      } on Exception catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$error')),
        );
      }
    }
  }
}

/// 详情正文：图片 + 富文本正文 + 元信息，统一在一个可滚动列里。
class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.entry,
    required this.assets,
    required this.supportDir,
  });

  final TimelineEntry entry;
  final AsyncValue<List<EntryAsset>> assets;
  final AsyncValue<String> supportDir;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 图片区：无图时不占位、不报错，assets 的各态都安全降级为空。
          assets.when(
            data: (list) => list.isEmpty
                ? const SizedBox.shrink()
                : _ImageGallery(
                    assets: list,
                    supportDir: supportDir.value,
                    entryId: entry.id,
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          // 正文区：优先用 quill 只读渲染；解析失败或为空串静默降级纯文本。
          _RichTextView(
            contentDelta: entry.contentDelta,
            plainText: entry.plainText,
          ),
          // 元信息区：日期 / 类型 / 笔记本 / 心情，跟随 AppTheme 排版。
          _MetaArea(entry: entry),
        ],
      ),
    );
  }
}

/// 富文本正文（只读）
///
/// 关键降级策略：contentDelta 为空串、`jsonDecode` 失败、或解析出的不是合法
/// Delta（非 List）时，一律静默回退 `Text(plainText)`——绝不让一条坏数据把详情页搞崩。
/// QuillController 在 initState 构建、dispose 释放；解析失败则保持为 null 走降级分支。
class _RichTextView extends StatefulWidget {
  const _RichTextView({required this.contentDelta, required this.plainText});

  final String? contentDelta;
  final String plainText;

  @override
  State<_RichTextView> createState() => _RichTextViewState();
}

/// 首图 Hero 标签（与时间轴卡片共用，W10 过渡动画）
/// 结构：`entry-thumb-<条目id>`；详情页只有第一张套 Hero，避免同页多个相同 tag。
String entryThumbHeroTag(int entryId) => 'entry-thumb-$entryId';

class _RichTextViewState extends State<_RichTextView> {
  QuillController? _controller;

  @override
  void initState() {
    super.initState();
    final delta = widget.contentDelta;
    if (delta != null && delta.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(delta);
        // Document.fromJson 要求 List 形态；Map/int 等合法 JSON 但非 Delta 也降级。
        if (decoded is List) {
          _controller = QuillController(
            document: Document.fromJson(decoded),
            selection: const TextSelection.collapsed(offset: 0),
            readOnly: true,
          );
        }
      } on Object {
        // 静默降级：任何解析异常都不上抛，下面回退纯文本。
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // scrollable:true 让编辑器自行滚动；外层是 SingleChildScrollView，
        // 高度不被约束，符合 QuillEditor 对「可滚动时必须无限高」的要求。
        child: QuillEditor.basic(
          controller: _controller!,
          config: const QuillEditorConfig(
            // 外层已经是 SingleChildScrollView：编辑器自己再开一个滚动视图
            // 会形成嵌套滚动——手势要抢、布局要两次测量，长正文下明显发涩。
            scrollable: false,
            showCursor: false,
            padding: EdgeInsets.zero,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        widget.plainText.isEmpty ? '（无正文）' : widget.plainText,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// 图片浏览：横向 PageView 翻页，多图时显示「n/N」指示。
///
/// 每张图都按显示宽度×设备像素比限制解码尺寸（cacheWidth），避免原图尺寸解码
/// 造成内存尖峰；点击打开全屏 Dialog，内部 InteractiveViewer 支持双指缩放。
class _ImageGallery extends StatefulWidget {
  const _ImageGallery({
    required this.assets,
    required this.supportDir,
    required this.entryId,
  });

  final List<EntryAsset> assets;
  final String? supportDir;
  final int entryId;

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  late final PageController _pageController;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.supportDir;
    // 支持目录尚未解析（理论上极短）时不渲染，避免拼出空基准路径。
    if (root == null) return const SizedBox.shrink();

    // 限制解码尺寸：屏幕宽度×DPR，让原图（动辄数 MB）只按显示需要解码。
    final cacheWidth =
        (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
            .round();
    final items = widget.assets;

    return Column(
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).width,
          child: PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, index) {
              // 必须走 preferredRelPath（medium→thumb→原图），绝不直接解码原图。
              final abs = p.join(root, items[index].preferredRelPath);
              final image = Image.file(
                File(abs),
                cacheWidth: cacheWidth,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.broken_image)),
              );
              final page = GestureDetector(
                onTap: () => _openFullscreen(context, abs, cacheWidth),
                child: image,
              );
              // 只有第一张接 Hero：与时间轴卡片共享标签，形成「卡片→详情」的连续动画
              if (index != 0) return page;
              return Hero(
                tag: entryThumbHeroTag(widget.entryId),
                child: page,
              );
            },
          ),
        ),
        if (items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_current + 1}/${items.length}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
      ],
    );
  }

  /// 全屏查看：InteractiveViewer 支持缩放/平移。
  ///
  /// W10：即便是全屏**也**限制解码尺寸。屏幕物理宽度通常 1080–1440px，
  /// 而 medium 长边 1600 已绰绰有余；若 preferredRelPath 回退到原图（历史数据未回填），
  /// 不加限制就会把 4000px 数 MB 的原图整个解码进内存，放大时很容易触发 OOM。
  void _openFullscreen(BuildContext context, String abs, int cacheWidth) {
    showDialog(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.file(
                  File(abs),
                  cacheWidth: cacheWidth,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 元信息区：日期、类型、笔记本、心情（1–5 档）。不写死颜色，跟随 AppTheme。
class _MetaArea extends StatelessWidget {
  const _MetaArea({required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      _MetaItem(icon: Icons.calendar_today_outlined, label: _formatDate(entry.entryDate)),
      _MetaItem(icon: Icons.label_outline, label: entry.type.label),
      if (entry.notebookName != null)
        _MetaItem(icon: Icons.book_outlined, label: entry.notebookName!),
      if (entry.mood != null)
        _MetaItem(icon: Icons.mood, label: '心情 ${entry.mood}/5'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }

  /// 手写日期格式，避免引入 intl 依赖（项目未直接依赖 intl）。
  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 元信息单行：图标 + 文案，复用主题文字样式。
class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 记录不存在 / 已删除的明确空态（区别于「加载中」与「报错」）。
class _NotFoundView extends StatelessWidget {
  const _NotFoundView();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_outlined,
              size: 56, color: cs.primary.withAlpha(120)),
          const SizedBox(height: 12),
          Text('记录不存在或已被删除',
              style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// 加载失败态（AsyncValue.error 第三层）。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
          ),
        ],
      ),
    );
  }
}
