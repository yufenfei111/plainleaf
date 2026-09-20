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
          title: Text(
            h.title.isEmpty ? '(无标题)' : h.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            h.plainText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(_typeLabels[h.type] ?? h.type),
          onTap: () => context.push('/editor?id=${h.id}'),
        );
      },
    );
  }
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