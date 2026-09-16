// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notebooks_dao.dart';

// ignore_for_file: type=lint
mixin _$NotebooksDaoMixin on DatabaseAccessor<PlainLeafDatabase> {
  $NotebooksTable get notebooks => attachedDatabase.notebooks;
  NotebooksDaoManager get managers => NotebooksDaoManager(this);
}

class NotebooksDaoManager {
  final _$NotebooksDaoMixin _db;
  NotebooksDaoManager(this._db);
  $$NotebooksTableTableManager get notebooks =>
      $$NotebooksTableTableManager(_db.attachedDatabase, _db.notebooks);
}
