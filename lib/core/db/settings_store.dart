import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

/// 配置读写（W9）
///
/// **为什么走数据库 settings_kv 而不是 shared_preferences**：
/// DEVELOPMENT.md 第 27 行有明确约定——「需要同步/备份的配置（主题、字体、备份计划）
/// → settings_kv；纯设备本地偏好（窗口尺寸、最近搜索）→ shared_preferences」。
/// 主题和字体是要跟着备份包一起走的，所以必须进库，不能图省事扔进 SP。
///
/// **为什么不写成 @DriftAccessor**：SettingsKv 早就在
/// `@DriftDatabase(tables: [...])` 列表里，生成代码已经暴露了 `db.settingsKv`
/// 这个 TableInfo。直接用 `db.select / into / update` 就够了，没必要为了一个
/// 增删改查跑一次 build_runner 把全量 `.g.dart` 重新生成一遍（那才是真正的风险源）。
///
/// 数据红线：删除配置项一律**软删**（deleted 置位），不做物理删除。
class SettingsStore {
  SettingsStore(this._db);

  final PlainLeafDatabase _db;

  /// 单个配置项的值流；不存在或已软删返回 null
  Stream<String?> watchString(String key) {
    return (_db.select(_db.settingsKv)
          ..where((t) => t.key.equals(key) & t.deleted.equals(false)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  /// 同步读取一次；不存在或已软删返回 null
  Future<String?> readString(String key) async {
    final row = await (_db.select(_db.settingsKv)
          ..where((t) => t.key.equals(key) & t.deleted.equals(false)))
        .getSingleOrNull();
    return row?.value;
  }

  /// 写入（upsert）。[value] 为 null 表示清除该配置项（软删）。
  Future<void> writeString(String key, String? value) async {
    await _db.transaction(() async {
      final existing = await (_db
              .select(_db.settingsKv)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();

      if (value == null) {
        if (existing == null) return;
        await (_db.update(_db.settingsKv)..where((t) => t.key.equals(key)))
            .write(
          SettingsKvCompanion(
            deleted: const Value(true),
            updatedAt: Value(DateTime.now()),
            version: Value(existing.version + 1),
          ),
        );
        return;
      }

      if (existing == null) {
        await _db.into(_db.settingsKv).insert(
              SettingsKvCompanion.insert(
                key: key,
                value: Value(value),
                uuid: const Uuid().v4(),
              ),
            );
        return;
      }

      await (_db.update(_db.settingsKv)..where((t) => t.key.equals(key))).write(
        SettingsKvCompanion(
          value: Value(value),
          deleted: const Value(false),
          updatedAt: Value(DateTime.now()),
          version: Value(existing.version + 1),
        ),
      );
    });
  }
}

/// 配置项的键名常量（避免散落魔法字符串，也方便备份/迁移时统一枚举）
abstract final class SettingKeys {
  /// 主题模式：system / light / dark
  static const themeMode = 'theme.mode';

  /// 字体缩放倍率（字符串形式的 double）
  static const textScale = 'text.scale';

  /// 强调色种子（ARGB int 的字符串形式）
  static const accentSeed = 'theme.accent_seed';
}
