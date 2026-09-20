// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tags_dao.dart';

// ignore_for_file: type=lint
mixin _$TagsDaoMixin on DatabaseAccessor<PlainLeafDatabase> {
  $TagsTable get tags => attachedDatabase.tags;
  $EntryTagsTable get entryTags => attachedDatabase.entryTags;
  TagsDaoManager get managers => TagsDaoManager(this);
}

class TagsDaoManager {
  final _$TagsDaoMixin _db;
  TagsDaoManager(this._db);
  $$TagsTableTableManager get tags =>
      $$TagsTableTableManager(_db.attachedDatabase, _db.tags);
  $$EntryTagsTableTableManager get entryTags =>
      $$EntryTagsTableTableManager(_db.attachedDatabase, _db.entryTags);
}
