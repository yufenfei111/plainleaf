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