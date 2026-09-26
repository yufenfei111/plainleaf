import 'dart:io';

import 'package:drift/drift.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/database.dart';
import '../errors/app_exception.dart';

/// 各平台可能放中文字体的位置。
///
/// 排序原则：**先给"单字体文件"（.ttf/.otf），再考虑集合容器（.ttc）**。
/// pdf 包的 TTF 解析器处理不了 .ttc（字体集合），遇到只会抛异常，
/// 所以候选里干脆不列它——让用户抽一次"导出失败"的盲盒没有意义。
const List<String> defaultCjkFontPaths = <String>[
  // Windows：黑体/楷体/仿宋都是随系统安装的单字体 TrueType，覆盖中文足够
  r'C:\Windows\Fonts\simhei.ttf',
  r'C:\Windows\Fonts\simkai.ttf',
  r'C:\Windows\Fonts\simfang.ttf',
  // Android：ROM 差异大，新一代镜像多为 NotoSansSC，老镜像常驻 Graphics
  '/system/fonts/NotoSansSC-Regular.otf',
  '/system/fonts/SourceHanSansCN-Regular.otf',
  '/system/fonts/MiSans-Regular.ttf',
  // Linux 桌面常说的 Noto CJK 往往落在 truetype/opentype 下
  '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttf',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttf',
];

/// 逐个尝试候选字体，**第一个能被 pdf 解析的**胜出。
///
/// 为什么不是"找到第一个文件就返回"：文件存在不等于能用（集合字体、权限、
/// 损坏的下载副本都会让解析器当场抛）。逐个试着解析一遍，比事后让用户碰上一次
/// "PDF 导出失败"便宜得多。
typedef FontLoader = Future<pw.Font?> Function(List<String> candidates);

Future<pw.Font?> loadCjkFont(List<String> candidates) async {
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final bytes = await file.readAsBytes();
      return pw.Font.ttf(bytes.buffer.asByteData());
    } on Object {
      // 换下一个候选
      continue;
    }
  }
  return null;
}

/// PDF 导出（W14）
///
/// **中文字体是这个功能的全部难点**，三条现实约束写在这里以免后人重踩：
/// ① pdf 包内置字体只有拉丁字符集，直接写中文会得到空白或方框；
/// ② 把一份完整中文字体（动辄 5–20MB）打包进 App 只为"偶尔导一次"，不划算；
/// ③ 所以走"运行时用系统字体"。**找不到就明确失败**（[ExportException]），
///    绝不退化成导出一份看起来成功、打开全是方块的 PDF——那种失败会一路带到
///    用户把文件发出去之后才被发现，是最坏的一种。
class PdfExporter {
  PdfExporter(this._db, {FontLoader? fontLoader, List<String>? fontCandidates})
      : _loadFont = fontLoader ?? loadCjkFont,
        _candidates = fontCandidates ?? defaultCjkFontPaths;

  final PlainLeafDatabase _db;
  final FontLoader _loadFont;
  final List<String> _candidates;

  /// 导出单条记录
  Future<Uint8List> exportEntry(int entryId) async {
    final entry = await (_db.select(_db.entries)
          ..where((x) => x.id.equals(entryId)))
        .getSingle();
    return exportEntries(<Entry>[entry]);
  }

  /// 导出全部未删除、已发布记录（按日期倒序）
  Future<Uint8List> exportAll() async {
    final rows = await (_db.select(_db.entries)
          ..where((x) => x.deleted.equals(false) & x.status.equals('normal'))
          ..orderBy([(x) => OrderingTerm.desc(x.entryDate)]))
        .get();
    return exportEntries(rows);
  }

  Future<Uint8List> exportEntries(List<Entry> entries) async {
    final font = await _loadFont(_candidates);
    if (font == null) {
      throw const ExportException(
        '当前设备找不到可用的中文字体，无法导出 PDF',
      );
    }
    return render(entries, font);
  }

  /// 渲染为 PDF 字节（把字体作为参数传进来，便于测试注入而不依赖系统字体）
  Future<Uint8List> render(List<Entry> entries, pw.Font font) async {
    final theme = pw.ThemeData.withFont(
      base: font,
      bold: font,
      italic: font,
    );
    final doc = pw.Document(theme: theme);
    for (final entry in entries) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          build: (context) => <pw.Widget>[
            pw.Text(
              entry.title.isEmpty ? '(无标题)' : entry.title,
              style: const pw.TextStyle(fontSize: 20),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              _subtitle(entry),
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 10),
            pw.Divider(),
            pw.SizedBox(height: 10),
            for (final line in _bodyLines(entry))
              pw.Text(
                line,
                style: const pw.TextStyle(fontSize: 13, lineSpacing: 4),
              ),
          ],
        ),
      );
    }
    return Uint8List.fromList(await doc.save());
  }

  /// 正文按行拆开：一个 Text 塞整段会让换行符变成空格，段落全糊在一起
  List<String> _bodyLines(Entry entry) {
    final text = entry.plainText;
    if (text.isEmpty) return const <String>['(无正文)'];
    final lines = text.split('\n');
    return lines.isEmpty ? const <String>['(无正文)'] : lines;
  }

  String _subtitle(Entry entry) {
    final d = entry.entryDate;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${typeLabel(entry)} · ${d.year}-${two(d.month)}-${two(d.day)}'
        '${entry.mood == null ? '' : ' · 心情：${entry.mood}'}';
  }

  /// 库里的类型标识 → 中文标签。
  /// 标签字面量必须与 timeline_entry.dart 的 [EntryType] 保持同步——
  /// 这里不直接引用那个枚举是因为它在 features 层，core 反向依赖就破了分层红线。
  static String typeLabel(Entry entry) => switch (entry.type) {
        'diary' => '日记',
        'note' => '笔记',
        'quick' => '速记',
        'todo' => '待办',
        _ => entry.type,
      };
}
