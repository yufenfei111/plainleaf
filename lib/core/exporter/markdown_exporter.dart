import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../media/asset_kind.dart';

/// Markdown 导出（W5，issue #14；W19 补齐附件清单）
///
/// 记录 → Markdown：标题 / 日期 / 类型 / 心情头 + 纯文本正文 + **附件清单**；
/// 全部导出时按日期倒序以 `---` 分隔。
///
/// ## 一条注释债的清理（W19）
/// W5 起本类的注释就写着「图片附件以『附件清单』形式列出」，而 `_render` 里
/// **根本没有这段代码** —— 图片也一样没被列出。这类"注释描述了未实现的行为"
/// 比没有注释更糟：读代码的人会以为自己漏看了某处，或者以为导出是完整的。
/// 现在实现与注释一致。
///
/// ## 为什么清单不限图片
/// 多格式附件之后，一条记录挂着的更可能是 PDF / Word。只列图片等于
/// 「导出成 Markdown 就不知道这条记录带了什么文件」——而导出的意义正是留一份
/// 可读的底。清单里带**类型 + 原始文件名 + 相对路径**：
/// 类型与文件名给人读，相对路径给脚本用（能从备份包里把文件捞回来）。
class MarkdownExporter {
  MarkdownExporter(this._db);

  final PlainLeafDatabase _db;

  Future<String> exportEntry(int entryId) async {
    final e = await (_db.select(_db.entries)
          ..where((x) => x.id.equals(entryId)))
        .getSingle();
    final grouped = await _assetsByEntry({entryId});
    return _render(e, grouped[entryId] ?? const <Asset>[]);
  }

  /// 导出全部未删除、已发布记录（按日期倒序）
  Future<String> exportAll() async {
    final rows = await (_db.select(_db.entries)
          ..where((x) => x.deleted.equals(false) & x.status.equals('normal'))
          ..orderBy([(x) => OrderingTerm.desc(x.entryDate)]))
        .get();
    final grouped = await _assetsByEntry(rows.map((r) => r.id).toSet());
    final buf = StringBuffer();
    for (final i in rows.indexed) {
      buf.writeln(_render(i.$2, grouped[i.$2.id] ?? const <Asset>[]));
      if (i.$1 != rows.length - 1) {
        buf.writeln();
        buf.writeln('---');
        buf.writeln();
      }
    }
    return buf.toString();
  }

  /// 一次取全部附件再按条目分组。
  ///
  /// 为什么不逐条查：`exportAll` 在一本用了一年的笔记里很容易几百条，
  /// 逐条查就是几百次往返。这里是**一次查询**，代价只有一点点内存。
  Future<Map<int, List<Asset>>> _assetsByEntry(Set<int> entryIds) async {
    if (entryIds.isEmpty) return const <int, List<Asset>>{};
    final rows = await (_db.select(_db.assets)
          ..where((a) => a.entryId.isIn(entryIds) & a.deleted.equals(false))
          ..orderBy([(a) => OrderingTerm.asc(a.sortIndex)]))
        .get();
    final grouped = <int, List<Asset>>{};
    for (final a in rows) {
      final eid = a.entryId;
      if (eid == null) continue;
      grouped.putIfAbsent(eid, () => <Asset>[]).add(a);
    }
    return grouped;
  }

  String _render(Entry e, List<Asset> assets) {
    final d = e.entryDate;
    final date = '${d.year}-${_p2(d.month)}-${_p2(d.day)}';
    final buf = StringBuffer();
    buf.writeln('# ${e.title.isEmpty ? '(无标题)' : e.title}');
    buf.writeln();
    buf.writeln('> $date ｜ ${e.type} ｜ 心情: ${e.mood ?? '-'}');
    buf.writeln();
    buf.writeln(e.plainText.isEmpty ? '(无正文)' : e.plainText);
    if (assets.isNotEmpty) {
      buf.writeln();
      buf.writeln('## 附件');
      for (final a in assets) {
        // 原始文件名可能为空（W17 之前落库的老数据），此时回退盘上文件名 ——
        // 至少还带扩展名，比留空强。
        final name = a.originalName ?? p.basename(a.relPath);
        final kind = AssetKind.fromStorage(a.kind);
        buf.writeln('- [${kind.label}] $name — `${a.relPath}`');
      }
    }
    return buf.toString();
  }

  String _p2(int n) => n.toString().padLeft(2, '0');
}
