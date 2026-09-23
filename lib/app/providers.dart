import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/open.dart';

import '../core/db/database.dart';
import '../core/db/settings_store.dart';
import '../core/storage/media_storage.dart';
import 'theme.dart';

/// 媒体私有目录服务（W4；路径约定 §4.3）
final mediaStorageProvider =
    Provider<MediaStorage>((ref) => MediaStorage());

/// App 支持目录的绝对路径（W6 性能改造）
/// 目的：列表卡片要「同步」把库内相对路径拼成绝对路径。
/// 此前每张卡都用 FutureBuilder 现解析一次，滑动时反复重建 Future
/// （且首帧必然是 loading 圈再跳变）——改成顶层取一次、往下传字符串，
/// 卡片里就是一次纯字符串拼接，不再有异步与跳变。
final supportDirProvider = FutureProvider<String>((ref) async {
  final dir = await ref.watch(mediaStorageProvider).supportDir();
  return dir.path;
});

/// 全局数据库单例（Riverpod 注入）
/// 分层红线：页面不直接触碰 DAO/文件系统，一律经由本 Provider 暴露的 Stream。
/// 测试覆盖方式：ProviderScope(overrides: [dbProvider.overrideWithValue(内存库)])
final dbProvider = Provider<PlainLeafDatabase>((ref) {
  final db = PlainLeafDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 配置读写（W9）：主题/字体这类「要跟着备份走」的偏好落 settings_kv，
/// 不放 shared_preferences——约定见 DEVELOPMENT.md 第 27 行。
final settingsStoreProvider =
    Provider<SettingsStore>((ref) => SettingsStore(ref.watch(dbProvider)));

/// 首屏外观快照（W10 收尾：消除启动闪屏）
///
/// 为什么需要它：三个外观 Controller 原本都是「build() 先返回默认值 → 异步从
/// settings_kv 读回 → 改 state」，于是首帧必然先把默认主题画出来，配置回来后
/// 再重绘一次——用户看到的就是启动那一下「闪」。把三件套在 runApp 之前读好、
/// 经 ProviderScope 注入，build() 直接拿到终值，这一帧重绘就没了。
///
/// 字段全部可空是刻意的：null 表示「没预读到」，Controller 退回原来的异步恢复
/// 路径。这样只 override dbProvider 的既有测试行为一字不差地保持不变。
class AppearanceSnapshot {
  const AppearanceSnapshot({this.themeMode, this.textScale, this.accentSeed});

  /// 空快照：什么都没预读到（默认实现，也是读取失败时的降级值）
  const AppearanceSnapshot.empty()
      : themeMode = null,
        textScale = null,
        accentSeed = null;

  final ThemeMode? themeMode;

  final double? textScale;

  final int? accentSeed;
}

/// 由 main() 在 runApp 之前预读并注入；未注入时为空快照（= 旧版行为）。
final initialAppearanceProvider =
    Provider<AppearanceSnapshot>((ref) => const AppearanceSnapshot.empty());

/// 预读三件套（主题模式 / 字体缩放 / 强调色种子）
///
/// 为什么只调三次 readString 而不给 SettingsStore 加批量方法：SettingsStore 是
/// 核心文件、不在本次改动范围内，而三次主键等值查询走的是同一个已打开的库，
/// 代价远小于为此牵动核心层。
///
/// 任何异常一律降级为空快照：「读不到偏好」绝不能升级成「启动不起来」。
Future<AppearanceSnapshot> readAppearanceSnapshot(PlainLeafDatabase db) async {
  final store = SettingsStore(db);
  try {
    final rawMode = await store.readString(SettingKeys.themeMode);
    final rawScale = await store.readString(SettingKeys.textScale);
    final rawSeed = await store.readString(SettingKeys.accentSeed);
    return AppearanceSnapshot(
      themeMode: _parseThemeMode(rawMode),
      textScale: _parseTextScale(rawScale),
      accentSeed: _parseAccentSeed(rawSeed),
    );
  } on Object {
    return const AppearanceSnapshot.empty();
  }
}

/// 解析一律「失败即 null」（交给默认值），不把损坏的偏好项当成致命错误抛出去
ThemeMode? _parseThemeMode(String? raw) {
  if (raw == null) return null;
  for (final mode in ThemeMode.values) {
    if (mode.name == raw) return mode;
  }
  return null;
}

double? _parseTextScale(String? raw) {
  final value = double.tryParse(raw ?? '');
  // 档位外的脏值直接丢弃：设置页只暴露 options，越界值画出来也没意义
  if (value == null || !TextScaleController.options.contains(value)) {
    return null;
  }
  return value;
}

int? _parseAccentSeed(String? raw) => int.tryParse(raw ?? '');

/// 主题模式（W9）。默认跟随系统；改动立即生效并异步持久化。
///
/// 为什么用 Notifier 而不是 StateProvider：切换主题要配套写库，
/// 把「改状态」和「落盘」收在一处，页面里就不会出现"改了状态忘记存"的漏网之鱼。
final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // 用 read 而不是 watch：预读快照是「一次性初值」，不该把整棵树挂上去。
    final preset = ref.read(initialAppearanceProvider).themeMode;
    // 预读命中就直接返回终值，省掉「默认 → 恢复」的那一次重绘
    if (preset != null) return preset;
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    try {
      final raw =
          await ref.read(settingsStoreProvider).readString(SettingKeys.themeMode);
      final mode = _parseThemeMode(raw);
      if (mode == null) return;
      state = mode;
    } on Object {
      // 配置读不出来（库未就绪/已销毁）不该影响启动：退回跟随系统。
      // 这里必须 on Object：disposed 后写 state 抛的是 StateError（Error 不是 Exception）。
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await ref
          .read(settingsStoreProvider)
          .writeString(SettingKeys.themeMode, mode.name);
    } on Object {
      // 持久化失败只影响"下次启动是否记得"，不当场打断交互。
    }
  }
}

/// 字体缩放（W9）。1.0 = 跟随系统。
final textScaleProvider =
    NotifierProvider<TextScaleController, double>(TextScaleController.new);

class TextScaleController extends Notifier<double> {
  /// 可选档位（覆盖小屏省空间到大字号无障碍）
  static const options = <double>[0.85, 1.0, 1.15, 1.3];

  @override
  double build() {
    final preset = ref.read(initialAppearanceProvider).textScale;
    if (preset != null) return preset;
    _restore();
    return 1.0;
  }

  Future<void> _restore() async {
    try {
      final raw =
          await ref.read(settingsStoreProvider).readString(SettingKeys.textScale);
      final next = _parseTextScale(raw);
      if (next == null) return;
      state = next;
    } on Object {
      // 同上：读不出来就用默认档
    }
  }

  Future<void> set(double scale) async {
    state = scale;
    try {
      await ref
          .read(settingsStoreProvider)
          .writeString(SettingKeys.textScale, '$scale');
    } on Object {
      // 忽略：不影响当前会话
    }
  }
}

/// 强调色种子（W9），存 ARGB32。
final accentSeedProvider =
    NotifierProvider<AccentSeedController, int>(AccentSeedController.new);

class AccentSeedController extends Notifier<int> {
  @override
  int build() {
    final preset = ref.read(initialAppearanceProvider).accentSeed;
    if (preset != null) return preset;
    _restore();
    return AppTheme.primary.toARGB32();
  }

  Future<void> _restore() async {
    try {
      final raw = await ref
          .read(settingsStoreProvider)
          .readString(SettingKeys.accentSeed);
      final next = _parseAccentSeed(raw);
      if (next == null) return;
      state = next;
    } on Object {
      // 忽略
    }
  }

  Future<void> set(int argb) async {
    state = argb;
    try {
      await ref
          .read(settingsStoreProvider)
          .writeString(SettingKeys.accentSeed, '$argb');
    } on Object {
      // 忽略
    }
  }
}

/// 测试/演示专用：宿主机内存库
/// Windows x64 的 Flutter SDK 不自带 sqlite3.dll（FTS5 需系统提供）。
/// 查找顺序：环境变量 PLAINLEAF_SQLITE3_DLL（指向完整路径）→ System32 → Git 目录。
/// CI（Linux）安装 libsqlite3-dev 后自动可用，无需此覆盖。
QueryExecutor openInMemoryDb() {
  if (Platform.isWindows) {
    final candidates = <String>[
      if (Platform.environment['PLAINLEAF_SQLITE3_DLL'] != null)
        Platform.environment['PLAINLEAF_SQLITE3_DLL']!,
      r'C:\Windows\System32\sqlite3.dll',
      r'C:\Program Files\Git\mingw64\bin\sqlite3.dll',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        open.overrideFor(
            OperatingSystem.windows, () => DynamicLibrary.open(path));
        break;
      }
    }
  }
  return NativeDatabase.memory();
}