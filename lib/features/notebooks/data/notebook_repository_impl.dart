import '../../../core/db/daos/notebooks_dao.dart';
import '../domain/entities/notebook_item.dart';
import '../domain/repositories/notebook_repository.dart';

/// [NotebookRepository] 的本地 Drift 实现
class LocalNotebookRepository implements NotebookRepository {
  const LocalNotebookRepository(this._dao);

  final NotebooksDao _dao;

  @override
  Stream<List<NotebookItem>> watchNotebooks() {
    return _dao.watchNotebooks().map(
          (rows) => rows
              .map((n) => NotebookItem(
                    id: n.id,
                    name: n.name,
                    space: n.space,
                    sortIndex: n.sortIndex,
                  ))
              .toList(growable: false),
        );
  }
}