import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// 解析结果：一条 Markdown 区块对应的待入库记录（纯数据，无 IO）
class ParsedEntry {
  const ParsedEntry({
    required this.title,
    required this.plainText,
    this.entryDate,
    this.type = EntryType.note,
    this.mood,
  });

  final String title;
  final String plainText;
  final DateTime? entryDate;
  final EntryType type;

  /// 心情 1–5（识别不到为 null）
  final int? mood;
}

/// Markdown 导入解析器（W9，纯 Dart、不依赖 Flutter，便于脱离 Widget 单测）。
///
/// 设计目标：能原样吃回本应用 W5 的 Markdown 导出格式
/// （# 标题 + `> 日期｜类型｜心情` 头信息 + 正文，多条以 `---` 分隔），
/// 同时兼容干净的简单 Markdown（标题/头信息行写法更自由）。
List<ParsedEntry> parseMarkdown(String text) {
  // 空输入/纯空白：直接返回空列表，不抛异常（调用方据此显示空态）
  if (text.trim().isEmpty) return const [];
  final blocks = _splitBlocks(text);
  if (blocks.isEmpty) return const [];
  return [for (final b in blocks) _parseBlock(b)];
}

/// 按 `---` 切分多条记录；单独成行的 `---` 即视为分隔符。
List<String> _splitBlocks(String text) {
  final blocks = <String>[];
  final current = <String>[];
  for (final line in text.split('\n')) {
    if (line.trim() == '---') {
      if (current.isNotEmpty) {
        blocks.add(current.join('\n'));
        current.clear();
      }
    } else {
      current.add(line);
    }
  }
  if (current.isNotEmpty) blocks.add(current.join('\n'));
  return blocks.where((b) => b.trim().isNotEmpty).toList();
}

ParsedEntry _parseBlock(String block) {
  String? title;
  DateTime? entryDate;
  var type = EntryType.note;
  int? mood;
  final bodyLines = <String>[];
  var titleFound = false;
  var bodyStarted = false;

  for (final raw in block.split('\n')) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      // 正文区内的空行保留为段落分隔
      if (bodyStarted) bodyLines.add(raw);
      continue;
    }
    // 导出格式的头信息行：`> 日期 ｜ 类型 ｜ 心情`
    if (trimmed.startsWith('>')) {
      _applyMeta(
        trimmed.substring(1).trim(),
        (d) => entryDate = d,
        (t) => type = t,
        (m) => mood = m,
      );
      // 头信息之后即进入正文区
      bodyStarted = true;
      continue;
    }
    // 标题：第一个以 # 开头的行（取掉 # 与空白）
    if (!titleFound && trimmed.startsWith('#')) {
      title = trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      titleFound = true;
      continue;
    }
    // 干净的「键：值」头信息行（中英文冒号），尚未进入正文时识别
    if (!bodyStarted && _isMetaLine(trimmed)) {
      _applyMeta(
        trimmed,
        (d) => entryDate = d,
        (t) => type = t,
        (m) => mood = m,
      );
      continue;
    }
    bodyStarted = true;
    bodyLines.add(raw);
  }

  // 标题回退：正文首行 → 占位「导入记录」
  final resolvedTitle = (title == null || title.isEmpty)
      ? _fallbackTitle(bodyLines)
      : title;

  final plainText = bodyLines.map(_stripMarkdown).join('\n').trim();
    return ParsedEntry(
    title: resolvedTitle,
    plainText: plainText,
    entryDate: entryDate,
    type: type,
    mood: mood,
  );
}

/// 无标题时取正文首行作标题；该首行不再重复进入正文（原地移除）。
String _fallbackTitle(List<String> bodyLines) {
  final idx = bodyLines.indexWhere((l) => _stripMarkdown(l).isNotEmpty);
  if (idx == -1) return '导入记录';
  final t = _stripMarkdown(bodyLines[idx]).trim();
  bodyLines.removeAt(idx);
  return t;
}

/// 判断一行是否为「键：值」形式的头信息行
bool _isMetaLine(String line) {
  if (!line.contains(RegExp(r'[:：]'))) return false;
  final key = line.split(RegExp(r'[:：]')).first.trim();
  return RegExp(r'^(日期|date|类型|type|心情|mood)$', caseSensitive: false)
      .hasMatch(key);
}

/// 解析一段头信息：导出格式是「日期 ｜ 类型 ｜ 心情」整体一行，
/// 干净格式则可能是独立的「键：值」行。统一按 ｜/| 先拆，再逐段识别。
void _applyMeta(
  String meta,
  void Function(DateTime?) setDate,
  void Function(EntryType) setType,
  void Function(int?) setMood,
) {
  final tokens = meta
      .split(RegExp(r'\s*[｜|]\s*'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.length > 1) {
    for (final t in tokens) {
      _applyToken(t, setDate, setType, setMood);
    }
  } else if (tokens.isNotEmpty) {
    _applyToken(tokens.single, setDate, setType, setMood);
  }
}

void _applyToken(
  String token,
  void Function(DateTime?) setDate,
  void Function(EntryType) setType,
  void Function(int?) setMood,
) {
  final kv = token.split(RegExp(r'[:：]'));
  final key = kv.length > 1 ? kv.first.trim() : null;
  final value = kv.length > 1 ? kv.sublist(1).join(':').trim() : token.trim();
  if (key != null) {
    if (key == '日期' || key.toLowerCase() == 'date') {
      final d = _parseDate(value);
      if (d != null) setDate(d);
      return;
    }
    if (key == '类型' || key.toLowerCase() == 'type') {
      final t = _typeFromName(value);
      if (t != null) setType(t);
      return;
    }
    if (key == '心情' || key.toLowerCase() == 'mood') {
      final m = int.tryParse(value);
      if (m != null) setMood(m);
      return;
    }
  }
  // 无键的裸值：尝试直接识别为日期或类型
  final d = _parseDate(token);
  if (d != null) {
    setDate(d);
    return;
  }
  final t = _typeFromName(token);
  if (t != null) setType(t);
}

/// 解析日期：兼容 - / . 三种分隔；只取开头 YYYY-MM-DD 部分（忽略可能尾随的时间）
DateTime? _parseDate(String s) {
  final v = s.trim().replaceAll(RegExp(r'[/.]'), '-');
  final match = RegExp(r'^\d{4}-\d{1,2}-\d{1,2}').firstMatch(v);
  if (match == null) return null;
  return DateTime.tryParse(match.group(0)!);
}

/// 按 name（如 diary）或 label（如 日记）映射到 EntryType
EntryType? _typeFromName(String s) {
  for (final v in EntryType.values) {
    if (v.name == s || v.label == s) return v;
  }
  return null;
}

/// 剥掉常见 Markdown 标记，保留可读文本。
/// 链接 [x](y) 保留 x；#、** 、*、>、`、列表前缀均去除，不残留符号。
String _stripMarkdown(String line) {
  var t = line;
  // 链接：保留显示文字，丢弃地址
  t = t.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  // 标题 / 引用 / 列表 前缀
  t = t.replaceFirst(RegExp(r'^#+\s*'), '');
  t = t.replaceFirst(RegExp(r'^>\s?'), '');
  t = t.replaceFirst(RegExp(r'^\s*([-*+]|\d+\.)\s+'), '');
  // 强调符号
  t = t.replaceAll(RegExp(r'[*_`]+'), '');
  return t.trim();
}
