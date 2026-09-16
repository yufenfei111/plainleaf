// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entries_dao.dart';

// ignore_for_file: type=lint
mixin _$EntriesDaoMixin on DatabaseAccessor<PlainLeafDatabase> {
  $EntriesTable get entries => attachedDatabase.entries;
  $AssetsTable get assets => attachedDatabase.assets;
  $NotebooksTable get notebooks => attachedDatabase.notebooks;
  EntriesDaoManager get managers => EntriesDaoManager(this);
}

class EntriesDaoManager {
  final _$EntriesDaoMixin _db;
  EntriesDaoManager(this._db);
  $$EntriesTableTableManager get entries =>
      $$EntriesTableTableManager(_db.attachedDatabase, _db.entries);
  $$AssetsTableTableManager get assets =>
      $$AssetsTableTableManager(_db.attachedDatabase, _db.assets);
  $$NotebooksTableTableManager get notebooks =>
      $$NotebooksTableTableManager(_db.attachedDatabase, _db.notebooks);
}
