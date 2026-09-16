import 'package:drift/drift.dart';

/// 素页 PlainLeaf 核心数据表
/// 依据：docs/DEVELOPMENT.md §4.3（对归档计划书 §7.2 的修正版）
/// 红线：所有业务表统一携带 uuid/created_at/updated_at/version/deleted 五字段
///（为 v1.0 后 WebDAV 双向 LWW 同步预留，第一版建表必须加）；删除一律软删除。

/// 笔记本：生活 / 学习双空间 + 自定义
/// space 枚举：life | study | custom
class Notebooks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().withLength(min: 36, max: 36)();
  TextColumn get name => text().withDefault(const Constant('未命名'))();
  TextColumn get space => text().withDefault(const Constant('life'))();
  IntColumn get coverColor => integer().nullable()();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [{uuid}];
}

/// 记录主表：统一承载日记/笔记/速记/待办
/// type：note|diary|quick|todo；status：draft|normal|archived
/// content_delta 存 flutter_quill Delta JSON（W3 编辑器接入）
/// metadata_json：日记模板问答、心情扩展等弹性内容（§4.3 修正 ③）
class Entries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().withLength(min: 36, max: 36)();
  IntColumn get notebookId => integer().nullable().references(Notebooks, #id)();
  TextColumn get type => text().withDefault(const Constant('note'))();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get contentDelta => text().withDefault(const Constant(''))();
  TextColumn get plainText => text().withDefault(const Constant(''))();
  IntColumn get mood => integer().nullable()();
  TextColumn get weatherJson => text().nullable()();
  TextColumn get locationJson => text().nullable()();
  TextColumn get metadataJson => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('normal'))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get entryDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [{uuid}];
}

/// 媒体资产：文件存文件系统（media/yyyy/mm/），库中只存相对路径
/// hashSha256：§4.3 修正 ①（SHA-1 已不安全，弃用计划书的 hash_sha1）
class Assets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().withLength(min: 36, max: 36)();
  IntColumn get entryId => integer().nullable().references(Entries, #id)();
  TextColumn get kind => text().withDefault(const Constant('image'))();
  TextColumn get relPath => text()();
  TextColumn get thumbPath => text().nullable()();
  TextColumn get mediumPath => text().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get exifJson => text().nullable()();
  TextColumn get hashSha256 => text().nullable()();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [{uuid}];
}

/// 标签
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().withLength(min: 36, max: 36)();
  TextColumn get name => text().unique()();
  IntColumn get color => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [{uuid}];
}

/// 条目-标签 多对多（纯关联表，无业务字段）
class EntryTags extends Table {
  IntColumn get entryId => integer().references(Entries, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {entryId, tagId};
}

/// 学习待办
/// completedAt：§4.3 修正 ②（学习统计「每日完成数」依赖完成时间）
class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().withLength(min: 36, max: 36)();
  IntColumn get entryId => integer().nullable().references(Entries, #id)();
  TextColumn get content => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [{uuid}];
}

/// 学习时长会话（番茄钟 W11 接入）
class StudySessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().withLength(min: 36, max: 36)();
  TextColumn get subject => text().withDefault(const Constant(''))();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationSec => integer().withDefault(const Constant(0))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [{uuid}];
}

/// 同步元数据（v1.0 后 WebDAV 队列预留）
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 需要同步/备份的配置（主题、字体、备份计划）；
/// 纯设备本地偏好走 shared_preferences，密钥走 flutter_secure_storage（§4.3 存储分工）
class SettingsKv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}