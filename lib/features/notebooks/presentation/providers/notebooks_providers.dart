import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../data/notebook_repository_impl.dart';
import '../../domain/entities/notebook_item.dart';
import '../../domain/repositories/notebook_repository.dart';

/// 笔记本仓库（UI → Provider → Repository → DAO 分层链路）
final notebookRepositoryProvider = Provider<NotebookRepository>((ref) {
  return LocalNotebookRepository(ref.watch(dbProvider).notebooksDao);
});

/// 笔记本数据流（页面 .when 消费三态）
final notebooksStreamProvider = StreamProvider<List<NotebookItem>>((ref) {
  return ref.watch(notebookRepositoryProvider).watchNotebooks();
});

/// 笔记本 id → 条目数（W10）：整页一次 GROUP BY，tile 不再各自 FutureBuilder
final notebookCountsProvider = StreamProvider<Map<int, int>>((ref) {
  return ref.watch(notebookRepositoryProvider).watchEntryCountsByNotebook();
});

/// 标签行视图（避免 UI 直接命名 Drift 生成类——分层红线）
class TagItem {
  const TagItem({required this.id, required this.name, this.parentId});

  final int id;
  final String name;
  final int? parentId;
}

/// 标签流（W5 标签管理）
final tagsStreamProvider = StreamProvider<List<TagItem>>((ref) {
  return ref
      .watch(dbProvider)
      .tagsDao
      .watchAll()
      .map((rows) => [
            for (final t in rows)
              TagItem(id: t.id, name: t.name, parentId: t.parentId),
          ]);
});