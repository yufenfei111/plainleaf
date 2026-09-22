import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:plainleaf/features/importer/data/markdown_import_service.dart';
import 'package:plainleaf/features/timeline/presentation/providers/timeline_providers.dart';

/// Markdown 导入页（W9）。
///
/// 当前唯一入口是「粘贴 Markdown 文本」：暂不做文件选择器，避免引入额外权限与依赖。
/// 页面只负责收集文本 + 调服务 + 把结果转成提示，不直接读写文件/数据库
/// （落库经由 timelineRepositoryProvider 注入的仓库，符合分层红线）。
class MarkdownImportPage extends ConsumerStatefulWidget {
  const MarkdownImportPage({super.key});

  @override
  ConsumerState<MarkdownImportPage> createState() => _MarkdownImportPageState();
}

class _MarkdownImportPageState extends ConsumerState<MarkdownImportPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('导入 Markdown')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '支持粘贴 Markdown 文本（含本应用导出的格式）。多条记录以 --- 分隔。',
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: '在此粘贴要导入的 Markdown 文本…',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                ),
                style: textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _onImport,
              icon: const Icon(Icons.upload),
              label: const Text('开始导入'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onImport() async {
    final text = _controller.text;
    if (text.trim().isEmpty) {
      _toast('请先粘贴要导入的 Markdown 文本');
      return;
    }
    try {
      // 落库经由仓库，页面不直接碰 DAO
      final repo = ref.read(timelineRepositoryProvider);
      final service = MarkdownImportService(repo);
      final count = await service.importMarkdown(text);
      if (!context.mounted) return;
      _toast('导入完成：成功 $count 条');
    } on Object catch (e) {
      if (!context.mounted) return;
      // 失败给明确错误，而不是白屏
      _toast('导入失败：$e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
