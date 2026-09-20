import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';

/// 全文搜索页（W5，issue #12）
/// FTS5 检索（entries_fts MATCH）+ 类型过滤；CJK 查询自动做前缀化预处理
/// （unicode61 下中文连续串是单 token，'学习' 需转 '学习*' 才能前缀命中）。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _queryCtrl = TextEditingController();
  String? _typeFilter; // null = 全部
  List<_SearchHit> _hits = const [];
  bool _searching = false;
  String? _error;

  static const _typeLabels = {
    'note': '笔记',
    'diary': '日记',
    'quick': '速记',
    'todo': '待办',
  };

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  /// 查询预处理：按空白拆词，每词加前缀星号（FTS5 prefix query）
  String _preprocess(String raw) {
    final words =
        raw.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    return words.map((w) => '$w*').join(' ');
  }

  Future<void> _search() async {
    final raw = _queryCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _hits = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final db = ref.read(dbProvider);
      final ids = await db.entriesDao.searchEntryIds(_preprocess(raw));
      if (!mounted) return;

      final hits = <_SearchHit>[];
      for (final id in ids) {
        final e = await db.entriesDao.findById(id);
        if (e == null || e.deleted) continue;
        if (_typeFilter != null && e.type != _typeFilter) continue;
        hits.add(_SearchHit(
          id: e.id,
          title: e.title,
          plainText: e.plainText,
          type: e.type,
          entryDate: e.entryDate,
        ));
      }
      setState(() {
        _hits = hits;
        _searching = false;
      });
    } on Exception catch (error) {
      setState(() {
        _error = '$error';
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _queryCtrl,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '搜索标题与正文…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _filterChip(context, null, '全部'),
                for (final e in _typeLabels.entries)
                  _filterChip(context, e.key, e.value),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _filterChip(BuildContext context, String? value, String label) {
    final selected = _typeFilter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _typeFilter = value);
          _search();
        },
      ),
    );
  }

  /// 查询词（去 FTS 的前缀星号，供高亮使用）
  List<String> get _terms => _queryCtrl.text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.endsWith('*') ? w.substring(0, w.length - 1) : w)
      .toList();

  Widget _hitText(
    BuildContext context,
    String text, {
    required int maxLines,
    TextStyle? base,
  }) {
    final body = base ??
        Theme.of(context).textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);
    final hit = body.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
      backgroundColor:
          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
    );
    return Text.rich(
      TextSpan(children: buildHighlightSpans(text, _terms, base: body, hit: hit)),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(child: Text('搜索失败：$_error'));
    }
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_queryCtrl.text.trim().isNotEmpty && _hits.isEmpty) {
      return const Center(child: Text('没有匹配的记录'));
    }
    if (_hits.isEmpty) {
      return const Center(child: Text('输入关键词开始搜索'));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: _hits.length,
      itemBuilder: (context, i) {
        final h = _hits[i];
        return ListTile(
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: _hitText(context, h.title.isEmpty ? '(无标题)' : h.title,
              maxLines: 1, base: Theme.of(context).textTheme.titleMedium),
          subtitle: _hitText(context, h.plainText,
              maxLines: 2, base: Theme.of(context).textTheme.bodySmall),
          trailing: Text(_typeLabels[h.type] ?? h.type),
          onTap: () => context.push('/editor?id=${h.id}'),
        );
      },
    );
  }
}

/// 关键词高亮切分（§5.3 验收项：搜索高亮）
/// 按命中区间把文本切成普通段/高亮段；terms 为空或无命中时返回单段，
/// 避免不必要的 RichText 拆分。大小写不敏感，重叠区间会合并。
List<InlineSpan> buildHighlightSpans(
  String text,
  List<String> terms, {
  required TextStyle base,
  required TextStyle hit,
}) {
  final lower = text.toLowerCase();
  final ranges = <List<int>>[];
  for (final term in terms) {
    if (term.isEmpty) continue;
    final needle = term.toLowerCase();
    var idx = lower.indexOf(needle);
    while (idx != -1) {
      ranges.add([idx, idx + term.length]);
      idx = lower.indexOf(needle, idx + term.length);
    }
  }
  if (ranges.isEmpty) return <InlineSpan>[TextSpan(text: text, style: base)];

  ranges.sort((a, b) => a[0].compareTo(b[0]));
  final merged = <List<int>>[ranges.first];
  for (final r in ranges.skip(1)) {
    final last = merged.last;
    if (r[0] <= last[1]) {
      last[1] = r[1] > last[1] ? r[1] : last[1];
    } else {
      merged.add(r);
    }
  }

  final spans = <InlineSpan>[];
  var pos = 0;
  for (final r in merged) {
    if (r[0] > pos) {
      spans.add(TextSpan(text: text.substring(pos, r[0]), style: base));
    }
    spans.add(TextSpan(text: text.substring(r[0], r[1]), style: hit));
    pos = r[1];
  }
  if (pos < text.length) {
    spans.add(TextSpan(text: text.substring(pos), style: base));
  }
  return spans;
}

class _SearchHit {
  const _SearchHit({
    required this.id,
    required this.title,
    required this.plainText,
    required this.type,
    required this.entryDate,
  });

  final int id;
  final String title;
  final String plainText;
  final String type;
  final DateTime entryDate;
}