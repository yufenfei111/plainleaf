import 'package:plainleaf/core/errors/app_exception.dart';
import 'package:plainleaf/features/importer/domain/markdown_importer.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';
import 'package:plainleaf/features/timeline/domain/repositories/timeline_repository.dart';

/// Markdown 落库服务（W9）：解析 → 逐条 saveEntry。
///
/// 分层：页面只调本服务，不直接碰 DAO/文件；异常统一经 Repository 包装。
class MarkdownImportService {
  MarkdownImportService(this._repo);

  final TimelineRepository _repo;

  /// 导入一段 Markdown 文本，返回成功写入的条数。
  ///
  /// 单条失败不中断整批（记下来继续导其余条目）。
  /// 仅当「解析出条目但全部写入失败」这种结构性异常时，才把原始错误包成
  /// [DatabaseException] 向上抛，供 UI 给出有意义的失败提示。
  Future<int> importMarkdown(String text, {int? notebookId}) async {
    final parsed = parseMarkdown(text);
    if (parsed.isEmpty) return 0;

    var ok = 0;
    Object? lastError;
    for (final p in parsed) {
      try {
        await _repo.saveEntry(
          EntryDraft(
            title: p.title,
            plainText: p.plainText,
            type: p.type,
            mood: p.mood,
            notebookId: notebookId,
            entryDate: p.entryDate,
            // contentDelta 默认空串：详情页会自动降级为 plainText 渲染，
            // 不为纯文本硬造 quill Delta（W8 已实现的降级链路）。
          ),
        );
        ok++;
      } on Object catch (e) {
        // 单条失败记下来，不中断整批
        lastError = e;
      }
    }

    if (ok == 0 && lastError != null) {
      throw DatabaseException('Markdown 导入失败：所有条目均未能保存', cause: lastError);
    }
    return ok;
  }
}
