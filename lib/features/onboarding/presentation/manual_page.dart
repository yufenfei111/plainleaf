import 'package:flutter/material.dart';

import '../data/onboarding_content.dart';
import 'manual_art.dart';

/// 内置操作手册（W22）
///
/// ## 为什么「默认收起」而不是全部铺开
/// 内容是 10 章、几十条，全部展开要滚很久才能扫一遍目录。收起状态下
/// 一屏能看完所有章节标题 + 一句话摘要，找东西靠扫视就够；
/// 真正要看的那一章点开即可。这是"手册"和"文章"的区别 —— 前者要能查。
///
/// ## 和引导页的关系
/// 引导页是"第一次打开时那 4 屏"，看完就过去了；手册是常驻的、随时可查的，
/// 入口在「我的 → 操作手册」。两者共用 [kManualSections] 之外的同一套事实来源，
/// 内容只写当前真实存在的功能。
class ManualPage extends StatelessWidget {
  const ManualPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('操作手册')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '下面按功能分章。点任意一章展开，没展开时这一行就是它的用途摘要。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final section in kManualSections) _SectionCard(section: section),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final ManualSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: Icon(section.icon, color: cs.primary),
          title: Text(
            section.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              section.summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in section.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 正文用 1.7 行高：手册多为中文长句，行距紧了很难读
                    Text(
                      entry.body,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
                    ),
                    // 只在光靠文字说不清的地方配图（手势方向 / 界面结构 / 流程顺序），
                    // 每条都配图反而会让手册变成图片流水
                    if (entry.art != null) ManualArtView(art: entry.art!),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
