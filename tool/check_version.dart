// ignore_for_file: avoid_print
//
// 版本号一致性校验（W14 起）—— CI 门禁，本地也应手动跑：
//     dart run tool/check_version.dart
//
// 为什么要有这个脚本：
// `version` 从 0.2.0+2 一路用了 4 周（W10 → W14）没人改，期间完成了 M3 与整个阶段 4
// 的前两周。原因是"改版本号"这件事既没有单一来源，也没有任何机械约束：
// pubspec.yaml 一处、关于页硬编码一处，两边一起停着，看起来完全"自洽"。
// 同一问题 W10 修过一次又复发，说明只能靠门禁拦住，靠记性拦不住。
//
// 校验规则：pubspec.yaml 的 `version: <name>+<build>` 必须与
// lib/app/app_version.dart 里的 `name` / `build` 常量严格一致。
import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    _fail('找不到 pubspec.yaml —— 请在项目根目录运行');
  }
  final versionRaw = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(pubspec.readAsStringSync())
      ?.group(1);
  if (versionRaw == null) {
    _fail('pubspec.yaml 里找不到 `version:` 行');
  }

  final plusIndex = versionRaw.indexOf('+');
  final expectedName =
      plusIndex == -1 ? versionRaw : versionRaw.substring(0, plusIndex);
  final expectedBuild =
      plusIndex == -1 ? null : versionRaw.substring(plusIndex + 1);

  final source = File('lib/app/app_version.dart');
  if (!source.existsSync()) {
    _fail('找不到 lib/app/app_version.dart');
  }
  final text = source.readAsStringSync();
  final actualName =
      RegExp(r"static const String name = '([^']+)'").firstMatch(text)?.group(1);
  final actualBuild =
      RegExp(r'static const int build = (\d+)').firstMatch(text)?.group(1);

  final problems = <String>[];
  if (actualName != expectedName) {
    problems.add(
        "app_version.dart 的 name = '$actualName'，而 pubspec.yaml 是 '$expectedName'");
  }
  if (actualBuild != expectedBuild) {
    problems.add(
        "app_version.dart 的 build = '$actualBuild'，而 pubspec.yaml 是 '$expectedBuild'");
  }

  if (problems.isNotEmpty) {
    print('版本号不一致（下面两处必须同步改）：');
    for (final problem in problems) {
      print('  ✗ $problem');
    }
    print('');
    print('改法：pubspec.yaml 的 version 与 lib/app/app_version.dart 一起改。');
    print('规则：`<里程碑线>+<buildNumber>`，buildNumber 取周次且单调递增。');
    exit(1);
  }

  print('版本号一致 ✓  version=$versionRaw'
      '（name=$actualName, build=$actualBuild）');
}

Never _fail(String message) {
  print('版本校验失败：$message');
  exit(1);
}
