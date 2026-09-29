import 'package:flutter/material.dart';

import '../data/onboarding_content.dart';

/// 手册里的示意图（W22）
///
/// 全部用 Widget 手工画，不引入图片资源也不新增依赖。每个图只表达**一件事**：
/// 空间关系（界面哪里有什么）、方向（手势往哪滑）、顺序（流程先做什么）。
///
/// 统一的画法约定：
/// - 外框用 [_ArtFrame]（虚线感的浅边框），让"这是示意图"一眼可辨，
///   不会和真实界面截图混淆；
/// - 颜色一律取自 `ColorScheme`，所以深浅色主题下都是对的；
/// - 每个图下方给一到两句注解（`caption`），补上图形说不清的那半句。
class ManualArtView extends StatelessWidget {
  const ManualArtView({super.key, required this.art});

  final ManualArt art;

  @override
  Widget build(BuildContext context) => switch (art) {
        ManualArt.mainTabs => const _MainTabsArt(),
        ManualArt.attachEntry => const _AttachEntryArt(),
        ManualArt.recordParts => const _RecordPartsArt(),
        ManualArt.viewerGestures => const _ViewerGesturesArt(),
        ManualArt.filterDimensions => const _FilterDimensionsArt(),
        ManualArt.backupFlow => const _BackupFlowArt(),
      };
}

// ───────────────────────────── 通用零件 ─────────────────────────────

/// 示意图的统一外框
class _ArtFrame extends StatelessWidget {
  const _ArtFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: child,
    );
  }
}

/// 图下方的注解
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }
}

/// 小圆角标签
class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: cs.onSurfaceVariant),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── 各示意图 ─────────────────────────────

/// 1. 主界面结构：底部四个 Tab，记录入口在时间轴页
class _MainTabsArt extends StatelessWidget {
  const _MainTabsArt();

  static const _tabs = ['时间轴', '相册', '学习', '我的'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _ArtFrame(
          child: Column(
            children: [
              // 内容区 + 右下角悬浮的「+」
              SizedBox(
                height: 56,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        '内容区',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.add, size: 18, color: cs.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // 底部导航
              Row(
                children: [
                  for (final t in _tabs)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t == _tabs.first ? cs.primaryContainer : cs.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          t,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: t == _tabs.first
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const _Caption('右下角带 + 的圆钮 = 新建记录；底部四个 Tab 切换功能区'),
      ],
    );
  }
}

/// 2. 附件条的三个入口，以及它们的关键差异
class _AttachEntryArt extends StatelessWidget {
  const _AttachEntryArt();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const items = [
      (Icons.photo_camera_outlined, '拍照', '压缩'),
      (Icons.photo_library_outlined, '相册选图', '压缩'),
      (Icons.attach_file, '选择文件', '原样'),
    ];
    return Column(
      children: [
        _ArtFrame(
          child: Row(
            children: [
              for (final (icon, label, mode) in items)
                Expanded(
                  child: Column(
                    children: [
                      Icon(icon, size: 26, color: cs.primary),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(fontSize: 11, color: cs.onSurface),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: mode == '原样'
                              ? cs.tertiaryContainer
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          mode,
                          style: TextStyle(
                            fontSize: 9.5,
                            color: mode == '原样'
                                ? cs.onTertiaryContainer
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const _Caption('照片会被压缩以节省空间；「选择文件」是原样导入，'
            'PDF、Word、压缩包都走它'),
      ],
    );
  }
}

/// 3. 一条记录上能挂的维度
class _RecordPartsArt extends StatelessWidget {
  const _RecordPartsArt();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _ArtFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '标题',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '正文（富文本：加粗 / 列表 / 待办 / 引用…）',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: cs.outlineVariant),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: const [
                  _Chip('日期', icon: Icons.event_outlined),
                  _Chip('心情', icon: Icons.mood_outlined),
                  _Chip('分类', icon: Icons.folder_outlined),
                  _Chip('标签（可多个）', icon: Icons.sell_outlined),
                  _Chip('附件', icon: Icons.attach_file),
                ],
              ),
            ],
          ),
        ),
        const _Caption('「分类」一条记录只能有一个；「标签」可以贴多个，还支持层级'),
      ],
    );
  }
}

/// 4. 全屏看图的三个手势
class _ViewerGesturesArt extends StatelessWidget {
  const _ViewerGesturesArt();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget arrow(IconData icon, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );

    return Column(
      children: [
        _ArtFrame(
          child: Column(
            children: [
              // 手机框里的图片
              Container(
                height: 62,
                margin: const EdgeInsets.symmetric(horizontal: 26),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 26,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  arrow(Icons.swap_horiz, '左右滑\n换一张'),
                  arrow(Icons.zoom_in, '双击\n放大'),
                  arrow(Icons.swipe_down, '下滑\n退出'),
                ],
              ),
            ],
          ),
        ),
        const _Caption('放大状态下单指拖动是「看细节」，不会误退出；'
            '要退出先双击还原或直接下滑'),
      ],
    );
  }
}

/// 5. 筛选的四个维度
class _FilterDimensionsArt extends StatelessWidget {
  const _FilterDimensionsArt();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _ArtFrame(
          child: Column(
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: const [
                  _Chip('记录类型'),
                  _Chip('笔记本'),
                  _Chip('标签'),
                  _Chip('附件类型', icon: Icons.attach_file),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '可叠加使用，越选越精确',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
        const _Caption('筛选是在数据库层完成的，所以几千条记录也不会变慢'),
      ],
    );
  }
}

/// 6. 备份的三步流程
class _BackupFlowArt extends StatelessWidget {
  const _BackupFlowArt();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget step(IconData icon, String title, String sub) => Column(
          children: [
            Icon(icon, size: 22, color: cs.primary),
            const SizedBox(height: 5),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
            ),
          ],
        );

    return Column(
      children: [
        _ArtFrame(
          child: Row(
            children: [
              Expanded(
                child: step(Icons.ios_share_outlined, '导出', '.plbk 备份包'),
              ),
              Icon(Icons.arrow_forward, size: 16, color: cs.outline),
              Expanded(
                child: step(Icons.cloud_upload_outlined, '传输', '网盘 / 数据线'),
              ),
              Icon(Icons.arrow_forward, size: 16, color: cs.outline),
              Expanded(
                child: step(Icons.restore_outlined, '恢复', '新设备导入'),
              ),
            ],
          ),
        ),
        const _Caption('.plbk 里既有数据库也有全部附件文件，是完整归档；'
            '设置密码后即使文件被别人拿到也解不开'),
      ],
    );
  }
}
