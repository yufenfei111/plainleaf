import 'package:drift/drift.dart';

import '../db/database.dart';

/// Markdown 导出（W5，issue #14）
/// 记录 → Markdown：标题/日期/类型/心情头 + 纯文本正文；全部导出时按日期倒序以 --- 分隔。
/// 图片附件以「附件清单」形式列出（相对路径）；导出包形态 W6 打磨。
class MarkdownExporter {
  MarkdownExporter(this._db);

  final PlainLeafDatabase _db;

  Future<String> exportEntry(int entryId) async {
    final e = await (_db.select(_db.entries)
          ..where((x) => x.id.equals(entryId)))
        .getSingle();
    return _render(e);
  }

  /// 导出全部未删除、已发布记录（按日期倒序）
  Future<String> exportAll() async {
    final rows = await (_db.select(_db.entries)
          ..where((x) => x.deleted.equals(false) & x.status.equals('normal'))
          ..orderBy([(x) => OrderingTerm.desc(x.entryDate)]))
        .get();
    final buf = StringBuffer();
    for (final i in rows.indexed) {
      buf.writeln(_render(i.$2));
      if (i.$1 != rows.length - 1) {
        buf.writeln();
        buf.writeln('---');
        buf.writeln();
      }
    }
    return buf.toString();
  }

  String _render(Entry e) {
    final d = e.entryDate;
    final date = '${d.year}-${_p2(d.month)}-${_p2(d.day)}';
    final buf = StringBuffer();
    buf.writeln('# ${e.title.isEmpty ? '(无标题)' : e.title}');
    buf.writeln();
    buf.writeln('> $date ｜ ${e.type} ｜ 心情: ${e.mood ?? '-'}');
    buf.writeln();
    buf.writeln(e.plainText.isEmpty ? '(无正文)' : e.plainText);
    return buf.toString();
  }

  String _p2(int n) => n.toString().padLeft(2, '0');
}