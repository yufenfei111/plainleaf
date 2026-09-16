/// 笔记本领域实体（纯 Dart）
/// space：life | study | custom
class NotebookItem {
  const NotebookItem({
    required this.id,
    required this.name,
    required this.space,
    this.sortIndex = 0,
  });

  final int id;
  final String name;
  final String space;
  final int sortIndex;
}