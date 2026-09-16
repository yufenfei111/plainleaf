import '../entities/notebook_item.dart';

/// 笔记本仓库接口（实现见 data/notebook_repository_impl.dart）
abstract interface class NotebookRepository {
  /// 未删除笔记本：按 sortIndex 排序（生活/学习双空间 + 自定义）
  Stream<List<NotebookItem>> watchNotebooks();
}