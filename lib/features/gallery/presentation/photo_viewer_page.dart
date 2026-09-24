import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../domain/entities/gallery_asset.dart';

/// 解码宽度上限（物理像素）
///
/// 超过这一档再多解也没有肉眼收益，只是白白把内存顶上去。
const int kViewerMaxCacheWidth = 2048;

/// 看图时的解码宽度 = 屏幕宽 × DPR，再夹一道上限
///
/// 为什么两道工序都不能少：
/// - ×DPR 是「屏幕有多少物理像素就解多少」，低于它放大即糊；
/// - 夹上限是因为原图动辄 4000px，在 3x/4x DPR 的机型上按 ×DPR 会解出比
///   屏幕需要的还大得多的位图（3000+ 宽 ≈ 十几 MB），属于典型的内存自伤。
int viewerCacheWidth(BuildContext context) {
  final wanted = MediaQuery.sizeOf(context).width *
      MediaQuery.devicePixelRatioOf(context);
  return math.min(kViewerMaxCacheWidth, math.max(1, wanted.round()));
}

/// 取图序列：**thumb → medium → 原图**（由粗到细）
///
/// 为什么要列一串而不是直接挑最优的一张：看图时第一优先级是「立刻有东西看」，
/// thumb 在网格滑动时大概率已经解码过同一份——按同一个 cacheWidth 命中缓存，
/// 首帧几乎零等待；清晰度由后面的层级补上，用户感知就是「从不空」，而不是先黑一下。
///
/// 相邻重复会被折叠：早期数据 thumb/medium 未回填时可能指回同一个相对路径，
/// 不折叠会白解码两次同一张图。
List<String> viewerImageStages(GalleryAsset asset) {
  // thumb/medium 可能没回填：先按「可能有 null」收成一列再逐个跳空，
  // 比 if-case 判空的写法更容易被 analyzer 接受（不触发 use_null_aware_elements）。
  final candidates = <String?>[
    asset.thumbPath,
    asset.mediumPath,
    asset.relPath,
  ];
  final stages = <String>[];
  for (final rel in candidates) {
    if (rel == null) continue;
    if (stages.isEmpty || stages.last != rel) stages.add(rel);
  }
  return stages;
}

/// 暗场之上的前景色
///
/// 看图页恒定用压暗底（colorScheme.scrim，深浅主题下都是压暗用的那个 token），
/// 前景按当前明暗反推：浅色主题取 surface（白），深色主题取 onSurface（浅灰）。
/// 全程不写死任何色值，主题怎么调整都不会跑偏。
Color stageForeground(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.onSurface
      : theme.colorScheme.surface;
}

/// 一次单指手势的方向：横向=翻页，纵向=关闭
///
/// 用原始事件定性一次方向，是因为 InteractiveViewer（更深的识别器）会先赢走
/// 竞技场；认清方向后，横向由我们自己驱动 PageController，纵向走下滑关闭。
enum _GestureAxis { horizontal, vertical }

/// 相册全屏浏览（W11）
///
/// 替代 W10 的过渡方案「点图跳详情」。三条关键取舍：
/// 1. **不走 go_router**：看图是「临时盖住全屏」的模态，既不需要可深链的 /photo
///    路由，也不该被底部 Tab 压住——直接 push 到根 Navigator；过渡沿用
///    app/transitions.dart 的口径（200ms 淡入 / 160ms 淡出）。
/// 2. **解码尺寸全程受限**（见 [viewerCacheWidth]）：全屏并不是「可以放肆解码原图」
///    的豁免区，恰恰相反——这里最容易出现一张几千像素的原图，所以每一级都必须带
///    cacheWidth，缩放也要有上下界。
/// 3. **交互保持克制**：只有翻页 / 缩放 / 关闭三件事，不做分享、保存、编辑。
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.assets,
    required this.initialIndex,
    required this.supportDir,
  });

  /// 当前相册已加载的图片（扁平顺序 = 网格顺序）
  final List<GalleryAsset> assets;

  /// 初始下标（点的是第几张就停在第几张）
  final int initialIndex;

  /// App 支持目录绝对路径；相对路径以此为基准拼接
  final String supportDir;

  /// 打开全屏浏览（相册网格的唯一入口）
  static Future<void> open(
    BuildContext context, {
    required List<GalleryAsset> assets,
    required int index,
    required String supportDir,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (context, animation, secondaryAnimation) =>
            PhotoViewerPage(
          assets: assets,
          initialIndex: index,
          supportDir: supportDir,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage>
    with TickerProviderStateMixin {
  late final PageController _page;
  late final AnimationController _bounce;

  int _index = 0;
  bool _zoomed = false;

  /// 下滑位移：拖拽期间实时更新，松手后交给回弹动画带回 0。
  /// 用 ValueNotifier 而不是 setState：位移变化只重建这一层动画包装，
  /// PageView 与里面的图片都不参与重建，拖动过程中才不会掉帧。
  final ValueNotifier<double> _dragOffset = ValueNotifier<double>(0);
  bool _dragging = false;
  double _dragFrom = 0;

  /// 参与手势的指针（id → 落点）；多指针（双指缩放）一概不进页级手势
  final Map<int, Offset> _pointers = <int, Offset>{};

  /// 本次手势已定性的方向；未定性前（没过[_gestureSlop]）先不跟手
  _GestureAxis? _axis;

  /// 手势起点页码与滚动位置（翻页手势的基准）
  int _startPage = 0;
  double _startPixels = 0;

  /// 最近一次横向速度（px/s），用于处理「轻甩一下」这种位移不到阈值的情况
  Duration? _lastMoveAt;
  double _lastMoveDx = 0;
  double _velocityX = 0;

  /// 认定「这是拖动手势」的最小位移
  static const double _gestureSlop = 18;

  /// 松手即关闭的位移阈值：够大才不会在「随便蹭一下」时被误关
  static const double _dismissThreshold = 120;

  /// 翻页：位移过 1/4 屏，或甩得够快（px/s）
  static const double _pageFractionThreshold = 0.25;
  static const double _flingVelocity = 600;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _page = PageController(initialPage: _index);
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _page.dispose();
    _bounce.dispose();
    _dragOffset.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    _axis = null;
    _lastMoveAt = null;
    _lastMoveDx = 0;
    _velocityX = 0;
    if (_pointers.length == 1 && _page.hasClients) {
      _startPage = (_page.page ?? _index.toDouble()).round();
      _startPixels = _page.position.pixels;
    }
  }

  /// 页级手势统一在这里分发（左右翻页 + 下滑关闭）
  ///
  /// 为什么是**收原始指针事件**而不是用 GestureDetector：InteractiveViewer 在命中
  /// 路径里是更深的一层，同一个 move 事件先到它手上，位移一过 slop 它就先在竞技场
  /// 里赢（竞技场在 pointer down 之后即关闭，先到先赢），外层 PageView 的横向拖拽
  /// 判负——「翻页」就翻不动了。原始事件不受竞技场裁决影响，所以这里按「先越过 slop
  /// 的方向」自己定性一次手势：横向自己推 PageController，纵向走下滑关闭。
  ///
  /// 两个准入条件：① 当前页未放大——放大后的单指拖拽是 InteractiveViewer 的
  /// 「平移看细节」，抢过来会让用户在端详局部时被误关，看图器最不能犯的错；
  /// ② 只有一个指针，双指缩放整体留给 InteractiveViewer。
  void _onPointerMove(PointerMoveEvent event) {
    final start = _pointers[event.pointer];
    if (start == null) return;
    if (_zoomed || _pointers.length != 1) return;
    final delta = event.position - start;
    _trackVelocity(event, delta.dx);
    _axis ??= _resolveAxis(delta);
    switch (_axis) {
      case _GestureAxis.horizontal:
        _dragHorizontally(delta.dx);
      case _GestureAxis.vertical:
        _dragVertically(delta.dy);
      case null:
        break;
    }
  }

  void _trackVelocity(PointerMoveEvent event, double dx) {
    final last = _lastMoveAt;
    if (last != null) {
      final seconds = (event.timeStamp - last).inMicroseconds /
          Duration.microsecondsPerSecond;
      if (seconds > 0) _velocityX = (dx - _lastMoveDx) / seconds;
    }
    _lastMoveAt = event.timeStamp;
    _lastMoveDx = dx;
  }

  _GestureAxis? _resolveAxis(Offset delta) {
    if (delta.distance <= _gestureSlop) return null;
    return delta.dx.abs() > delta.dy.abs()
        ? _GestureAxis.horizontal
        : _GestureAxis.vertical;
  }

  /// 横向：跟手滚动。直接推 PageController 的滚动位置，而不是 setState——
  /// 让这次拖动只重排在树上的页面，不再重跑任何 build。
  void _dragHorizontally(double dx) {
    if (!_page.hasClients) return;
    final position = _page.position;
    final target = (_startPixels - dx)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _page.jumpTo(target);
  }

  /// 纵向：整层跟着手指走，同时压暗背景，暗示「要退回相册了」
  void _dragVertically(double dy) {
    _dragging = true;
    _dragOffset.value = dy;
  }

  void _onPointerUp(PointerUpEvent event) {
    final axis = _axis;
    _pointers.remove(event.pointer);
    _axis = null;
    _finish(axis);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    final axis = _axis;
    _pointers.remove(event.pointer);
    _axis = null;
    _finish(axis);
  }

  void _finish(_GestureAxis? axis) {
    switch (axis) {
      case _GestureAxis.horizontal:
        _endHorizontalSwipe();
      case _GestureAxis.vertical:
        _endDrag();
      case null:
        break;
    }
  }

  /// 翻页落位：过 1/4 屏就翻过去；位移不够但甩得够快也翻；都不满足就回原处。
  /// 200ms / easeOutCubic，与全 App 过渡同口径。
  void _endHorizontalSwipe() {
    if (!_page.hasClients) return;
    final movedPages = (_page.page ?? _startPage.toDouble()) - _startPage;
    final flung = _velocityX.abs() > _flingVelocity;
    var target = _startPage;
    if (movedPages <= -_pageFractionThreshold || (flung && movedPages < 0)) {
      target = _startPage + 1;
    } else if (movedPages >= _pageFractionThreshold ||
        (flung && movedPages > 0)) {
      target = _startPage - 1;
    }
    _page.animateToPage(
      target.clamp(0, widget.assets.length - 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _endDrag() {
    if (!_dragging) return;
    final passed = _dragOffset.value > _dismissThreshold;
    _dragging = false;
    if (passed) {
      // 关闭动画交给路由自身的反向过渡，不额外叠一套
      _dragOffset.value = 0;
      Navigator.of(context).pop();
      return;
    }
    // 未过阈值：记下当前位移，由回弹动画的 0→1 进度带回 0
    _dragFrom = _dragOffset.value;
    _dragOffset.value = 0;
    _bounce.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cacheWidth = viewerCacheWidth(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.scrim,
      body: AnimatedBuilder(
        // 合并两个来源：拖拽的实时位移 + 松手后的回弹动画
        animation: Listenable.merge(<Listenable>[_bounce, _dragOffset]),
        builder: (context, child) {
          // 拖拽中直接读实时位移；松手后由回弹进度把它带回 0
          final dy =
              _dragging ? _dragOffset.value : _dragFrom * (1 - _bounce.value);
          // 拖拽时整层（含背景）同步变淡：底下的相册透出来，暗示「要退回去了」
          final fade = (1 - dy.abs() / 320).clamp(0.35, 1.0).toDouble();
          return Transform.translate(
            offset: Offset(0, dy),
            child: Opacity(opacity: fade, child: child),
          );
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _page,
                itemCount: widget.assets.length,
                onPageChanged: (i) => setState(() {
                  _index = i;
                  // 翻页后回到未放大；每张页各自持有自己的变换，互不影响
                  _zoomed = false;
                }),
                itemBuilder: (context, i) => _ViewerItem(
                  // key 用图片 id：同一张图进出屏幕时复用变换状态，换成另一张必须重置
                  key: ValueKey<int>(widget.assets[i].id),
                  asset: widget.assets[i],
                  supportDir: widget.supportDir,
                  cacheWidth: cacheWidth,
                  onZoomChanged: (zoomed) {
                    if (_zoomed == zoomed) return;
                    setState(() => _zoomed = zoomed);
                  },
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(width: 16),
                      Text(
                        '${_index + 1}/${widget.assets.length}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: stageForeground(context),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '关闭',
                        icon: Icon(
                          Icons.close,
                          color: stageForeground(context),
                        ),
                        // 触控目标 ≥44dp（IconButton 默认已够，这里显式钉住口径）
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单页图片：InteractiveViewer + 分级渐进解码
///
/// 为什么同一时刻最多两级在场：三级全驻等于三份全屏位图，翻几页就会把
/// ImageCache 挤满（96MB 上限），网格那边的缩略图被淘汰，回头再滑回去要集体重解码。
/// 细一级出帧后，旧的粗一级随即退场，只留最新版本。
class _ViewerItem extends StatefulWidget {
  const _ViewerItem({
    super.key,
    required this.asset,
    required this.supportDir,
    required this.cacheWidth,
    required this.onZoomChanged,
  });

  final GalleryAsset asset;
  final String supportDir;
  final int cacheWidth;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ViewerItem> createState() => _ViewerItemState();
}

class _ViewerItemState extends State<_ViewerItem>
    with SingleTickerProviderStateMixin {
  /// 缩放下界 1×（看的就是「恰好铺满」），上界 4×：
  /// 再往上只是在插值放大同一份像素，看不到更多细节——解码尺寸早已被 cacheWidth
  /// 定死——却会让平移边界变得难以预期，也没有额外的信息量。
  static const double maxScale = 4;

  /// 双击放大的落点倍率
  static const double doubleTapScale = 2.5;

  /// 认定为「放大态」的阈值（留一点余量，避免手指微抖就当成了缩放）
  static const double zoomThreshold = 1.15;

  final TransformationController _transform = TransformationController();
  late final AnimationController _zoomAnim;
  Animation<Matrix4>? _zoomTween;

  bool _zoomed = false;

  /// 已出帧的层级（作为底图顶到细一级出帧为止，防止升级瞬间闪空）
  int _ready = -1;

  /// 当前正在解码/展示的层级
  int _requested = 0;

  List<String> get _stages => viewerImageStages(widget.asset);

  /// 允许取到的最细层级
  ///
  /// 未放大时停在 medium 那一档就够了（按屏宽解码，medium 长边 1600 已覆盖）；
  /// 只有放大后才需要原图撑住局部细节。没有 medium 的历史数据例外：
  /// 那时静止状态也得是原图，否则 thumb 拉满屏等于没看清。
  int get _target {
    final stages = _stages;
    if (_zoomed) return stages.length - 1;
    final medium = widget.asset.mediumPath;
    if (medium == null) return stages.length - 1;
    final at = stages.indexOf(medium);
    return at < 0 ? stages.length - 1 : at;
  }

  @override
  void initState() {
    super.initState();
    _zoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(_tickZoom);
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    _zoomAnim.dispose();
    super.dispose();
  }

  /// 变换状态更新统一延到帧末：frameBuilder / errorBuilder 都是在构建-绘制阶段
  /// 被回调的，当场 setState 会撞上「正在构建中」的断言。
  void _mutate(VoidCallback update) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(update);
    });
  }

  void _onFrame(int stage) {
    if (stage <= _ready) return;
    _mutate(() {
      _ready = stage;
      _requested = math.min(stage + 1, _target);
    });
  }

  /// 某一级缺失（历史数据只回填了一部分、文件被清过）就往细一级跳。
  ///
  /// 这里刻意**不看 [_target]**：既然中等那一档取不到，静止时的「够清楚」前提
  /// 已经不成立，继续往下试才是唯一出路；同时因为层级只增不减，不存在
  /// 反复重建同一张失败图的循环。
  void _skip(int stage) {
    if (stage >= _stages.length - 1) return;
    _mutate(() => _requested = math.min(stage + 1, _stages.length - 1));
  }

  void _onTransform() {
    final next = _transform.value.getMaxScaleOnAxis() > zoomThreshold;
    if (next == _zoomed) return;
    _zoomed = next;
    widget.onZoomChanged(next);
    _mutate(() {
      // 放大态：允许再往细一级走；还原后停在已出帧的最细一级即可
      _requested = next
          ? math.min(_ready + 1, _target)
          : math.min(_ready < 0 ? 0 : _ready, _target);
    });
  }

  /// 双击：围绕手指落点放大 / 还原（200ms，与全 App 过渡同口径）
  void _onDoubleTapDown(TapDownDetails details) {
    final from = _transform.value.clone();
    final to =
        _zoomed ? Matrix4.identity() : _zoomAround(details.localPosition);
    _zoomTween = Matrix4Tween(begin: from, end: to).animate(
      CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic),
    );
    _zoomAnim.forward(from: 0);
  }

  void _tickZoom() {
    final tween = _zoomTween;
    if (tween == null) return;
    _transform.value = tween.value;
  }

  /// 围绕焦点放大：不这样做的话，手指按住的那一点会跑出屏幕，手感是「被甩出去」
  Matrix4 _zoomAround(Offset focal) {
    return Matrix4.identity()
      ..translateByDouble(
        -focal.dx * (doubleTapScale - 1),
        -focal.dy * (doubleTapScale - 1),
        0,
        1,
      )
      ..scaleByDouble(doubleTapScale, doubleTapScale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final stages = _stages;
    final requested = _requested.clamp(0, stages.length - 1);
    return GestureDetector(
      onDoubleTapDown: _onDoubleTapDown,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: maxScale,
        // 未放大时把单指手势让给上层的「下滑关闭」；放大后才启用平移看细节
        panEnabled: _zoomed,
        child: SizedBox.expand(
          child: Stack(
            children: [
              if (_ready >= 0 && _ready != requested)
                Positioned.fill(child: _layer(_ready)),
              Positioned.fill(child: _layer(requested)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layer(int stage) {
    final rel = _stages[stage];
    return Image.file(
      File(p.join(widget.supportDir, rel)),
      // 图片三要素之三：无论哪一级都必须带 cacheWidth
      cacheWidth: widget.cacheWidth,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronousLoad) {
        if (frame != null) _onFrame(stage);
        return child;
      },
      errorBuilder: (context, error, stackTrace) {
        _skip(stage);
        if (stage < _stages.length - 1) return const SizedBox.shrink();
        return Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: stageForeground(context),
          ),
        );
      },
    );
  }
}
