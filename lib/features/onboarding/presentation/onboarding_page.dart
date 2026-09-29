import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/db/settings_store.dart';
import '../data/onboarding_content.dart';

/// 新手引导（W22）
///
/// ## 什么时候出现
/// 只在**第一次打开 App** 时出现：`main.dart` 在启动阶段读
/// `settings_kv` 里的 [SettingKeys.onboardingSeen]，没读过就把初始路由设成本页。
/// 跑完（或点跳过）会写入标记，之后不再打扰。
///
/// ## 为什么用「独立路由」而不是「压在首页上的浮层」
/// 浮层要处理"底下的首页是否已经加载完 / 手势穿透 / 返回键"三件事，
/// 而且用户跳过时底下那一层会闪一下。做成独立路由则天然是干净的：
/// 引导结束后 `go('/timeline')`，首页第一次构建就在正确的位置。
///
/// ## 标记写入失败怎么办
/// **不阻断进入 App**。「没记住"已看过"」的后果只是下次再显示一遍引导，
/// 而"因为写配置失败把用户挡在门外"是不可接受的 —— 所以这里 try 住，
/// 失败也照常进主界面。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  bool get _isLast => _index == kOnboardingSlides.length - 1;

  /// 写入「已看过」标记并进入主界面。
  ///
  /// 注意顺序：**先写完标记再跳转**，否则用户可能在写入完成前就把 App 杀掉，
  /// 下次启动又从头看一遍。
  Future<void> _finish() async {
    try {
      await SettingsStore(ref.read(dbProvider))
          .writeString(SettingKeys.onboardingSeen, '1');
    } on Object {
      // 写失败不阻断：下次再显示一遍引导是可以接受的代价
    }
    if (!mounted) return;
    context.go('/timeline');
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _page.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 跳过：任何时候都能一步进主界面。放在右上角是惯例位置，
            // 不抢视觉重心，但需要时一眼能找到。
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('onboarding-skip'),
                onPressed: _finish,
                child: const Text('跳过'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: kOnboardingSlides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) =>
                    _SlideView(slide: kOnboardingSlides[i]),
              ),
            ),
            _Dots(count: kOnboardingSlides.length, index: _index),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('onboarding-next'),
                  onPressed: _next,
                  child: Text(_isLast ? '开始使用' : '下一步'),
                ),
              ),
            ),
            // 最后一页给一句轻提示，避免"点完按钮不知道发生了什么"
            SizedBox(
              height: 28,
              child: _isLast
                  ? Center(
                      child: Text(
                        '引导随时可以在「我的 → 操作手册」里重看',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单页引导内容：图标 + 标题 + 一句话 + 要点
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(slide.icon, size: 52, color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 36),
          Text(
            slide.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          for (final item in slide.highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 页面指示点：当前页用主色并拉长，其余是小圆点
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? cs.primary : cs.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
