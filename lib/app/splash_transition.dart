import 'package:flutter/material.dart';

/// 启动进入过渡（W15 体验升级 · 需求 1）
///
/// ## 为什么不用 anime.js / GSAP 这类 JS 动画库
/// 它们是浏览器库（依赖 DOM 与 WAAPI），而素页是 Flutter——没有 DOM 可操作。
/// 唯一"能用"的接法是内嵌 WebView 承载动画，代价是冷启动必须先初始化 WebView 引擎，
/// 与项目「冷启动 < 2s」的性能红线正面冲突；而收益只是一段不到一秒的过场。
/// 所以这里用原生 `AnimationController`，但**缓动曲线对齐 anime.js 的定义**：
/// `easeOutExpo` 与 `cubicBezier(0.22, 1, 0.36, 1)`（anime v4 的 cubic-bezier solver 同参数），
/// 动效语言与那份素材保持一致，不浪费。
///
/// ## 三条硬约束（都来自本项目真实踩过的坑）
/// ① **一次性动画**：forward 完成即静止，绝不留常驻 ticker ——
///    常驻动画会让 `pumpAndSettle` 永远等不到静止，整套 Widget 测试挂死（W10/W13 各踩过一次）。
/// ② **不改变既有树结构**：`child` **始终**在树中、不做布局变换，过场层用 `IgnorePointer`
///    让点击穿透。于是 `find.*` 与 `tap` 类断言全部不受影响——173 条旧用例不必为一层
///    视觉过渡改写（这是本轮最容易被忽视的回归风险）。
/// ③ **不阻塞首帧**：过场只是覆盖层，与数据加载并行；不做"先播完动画再加载"的串行结构。
///
/// 无障碍：系统开启「减少动态效果」时立即完成，不播放任何过渡。
class SplashTransition extends StatefulWidget {
  const SplashTransition({
    super.key,
    required this.child,
    this.enabled = true,
    this.duration = const Duration(milliseconds: 880),
  });

  final Widget child;

  /// 关掉即完全不出过场层（测试与低端机降级用）
  final bool enabled;

  final Duration duration;

  @override
  State<SplashTransition> createState() => _SplashTransitionState();
}

class _SplashTransitionState extends State<SplashTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// 标记入场（0 → 520ms）：缩放 + 淡入，easeOutExpo
  late final Animation<double> _markIn;

  /// 名称入场（123 → 537ms）：上移 + 淡入，cubicBezier(0.22, 1, 0.36, 1)
  late final Animation<double> _nameIn;

  /// 过场层退场（616 → 880ms）
  late final Animation<double> _coverOut;

  bool _finished = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _markIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.59, curve: Curves.easeOutExpo),
    );
    _nameIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.14, 0.61, curve: Cubic(0.22, 1, 0.36, 1)),
    );
    _coverOut = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.70, 1, curve: Curves.easeInOutCubic),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _finished = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _finished) return;
    _started = true;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!widget.enabled || reduceMotion) {
      // 直接标记完成：这里不用 setState，因为 didChangeDependencies 之后必然重新 build
      _finished = true;
      return;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // 过场层不拦截点击：动画期间（以及测试里）既有交互一律照常可用
        IgnorePointer(
          key: const Key('splash-overlay'),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final mark = _markIn.value.clamp(0.0, 1.0);
              final name = _nameIn.value.clamp(0.0, 1.0);
              return Opacity(
                opacity: (1 - _coverOut.value).clamp(0.0, 1.0),
                child: ColoredBox(
                  color: scheme.surface,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: 0.86 + 0.14 * mark,
                          child: Opacity(
                            opacity: mark,
                            child: SizedBox(
                              width: 92,
                              height: 92,
                              child: CustomPaint(
                                painter: _PlainLeafMarkPainter(
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Transform.translate(
                          offset: Offset(0, 14 * (1 - name)),
                          child: Opacity(
                            opacity: name,
                            // 用 RichText 而不是 Text：一是便于精细控制字距，
                            // 二是它不会被 find.text 命中，过场层因此不会干扰
                            // 任何以文本为锚点的既有断言。
                            child: RichText(
                              text: TextSpan(
                                text: '素页',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      letterSpacing: 6,
                                      color: scheme.onSurface,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 过场标记：一张带文字的纸页（纯几何绘制，不引入图片资源，也就不碰 pubspec 的 assets）
class _PlainLeafMarkPainter extends CustomPainter {
  _PlainLeafMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.width * 0.16);
    final rect = Rect.fromLTWH(
      size.width * 0.16,
      size.height * 0.09,
      size.width * 0.68,
      size.height * 0.82,
    );
    final page = RRect.fromRectAndRadius(rect, radius);

    canvas.drawRRect(page, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawRRect(
      page,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.052
        ..strokeJoin = StrokeJoin.round,
    );

    final line = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = size.width * 0.042
      ..strokeCap = StrokeCap.round;
    for (final factor in <double>[0.38, 0.56, 0.74]) {
      final y = rect.top + rect.height * factor;
      // 最后一条画短一点，像一段没收尾的句子
      final right = factor == 0.74
          ? rect.left + rect.width * 0.60
          : rect.left + rect.width * 0.82;
      canvas.drawLine(
        Offset(rect.left + rect.width * 0.18, y),
        Offset(right, y),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlainLeafMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
