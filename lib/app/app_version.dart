/// App 版本信息（W14 起）—— 代码侧的**唯一来源**。
///
/// 为什么要有这个文件：
/// 关于页此前在 `settings_page.dart` 里硬编码 `v0.2.0（M2）`，与 `pubspec.yaml`
/// 的 `version` 是两处独立维护。两边一起停在 0.2.0，从 W10 末端一直漂到 W14：
/// 横跨 **W11–W14 四个周次**的工作量、含 M3 里程碑（日历时间 9/22–9/26）。
/// 结果是装到真机上「看不出变化」，也无法据此判断是否装上了新包。
/// 同一个坑 W10 修过一次，说明"记得同步手改"这种约定防不住。
///
/// 现在的规则：
/// - `pubspec.yaml` 的 `version` 仍是**构建真源**（Flutter 与 Android 都读它）；
/// - 本文件的常量是**展示真源**，由 `tool/check_version.dart` 强制与之一致；
/// - CI（`.github/workflows/ci.yml`）在 analyze 之前跑那个校验，不一致直接红。
///
/// 格式约定：`version: <里程碑线>+<buildNumber>`，buildNumber 取**周次**且单调递增，
/// 例如 `0.4.0-beta+14` 表示"阶段 4 第 14 周"。
class AppVersion {
  const AppVersion._();

  /// 与 `pubspec.yaml` 的 `version` 中 `+` 之前的部分严格一致
  static const String name = '0.4.0-beta';

  /// 与 `pubspec.yaml` 的 `version` 中 `+` 之后的部分严格一致。
  /// Android 的 versionCode 也取它 —— 单调递增，"装没装上新的"一眼可判。
  static const int build = 14;

  /// 当前开发阶段（纯展示，不参与构建）
  static const String stageLabel = '阶段 4 开发中 · W14';

  /// 关于页展示用：`v0.4.0-beta (build 14)`
  static String get display => 'v$name (build $build)';
}
