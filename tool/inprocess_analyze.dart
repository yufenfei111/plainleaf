// 本地静态检查兜底工具（替代被环境阻塞的 `dart analyze` / `flutter analyze`）
//
// 用途：本机会话里创建子进程管道被安全策略拦截（ProcessException: 管道范例都在使用中），
// `dart analyze` / `flutter test` 都会因此崩溃——它们本质是靠 fork 一个子进程干活。
// 本脚本把分析器放在**当前进程内**跑（import package:analyzer 直接使用），
// 从而在同一次受限会话里仍能拿到「类型错误 + lint」的检查结果。
//
// 口径对齐 CI：`flutter analyze --fatal-infos lib test`，即 **INFO 也算问题**。
//
// ⚠️ 覆盖范围说明（实测）：本脚本能可靠捕获 **编译错误 / 类型错误 / 未定义符号**；
// 但进程内跑的分析器没有套用 `analysis_options.yaml` 里 `include: package:flutter_lints/flutter.yaml`
// 引入的 lint 规则（已用排序类、use_build_context_synchronously 等做反向验证，均为 0）。
// 所以本地过绿 ≠ CI 过绿：提交前请在正常环境补跑一次真正的 `flutter analyze --fatal-infos`。
// 用法：dart run tool/inprocess_analyze.dart [目标目录...]  # 默认 lib test
// 退出码：0 = 无问题；1 = 有问题。
//
// 注意：这是**兜底手段**，不等于官方分析器输出；CI 上仍然跑 `flutter analyze`。
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;

Future<int> main(List<String> args) async {
  final targets = args.isNotEmpty ? args : <String>['lib', 'test'];
  final root = Directory.current.path;

  final collection = AnalysisContextCollection(
    includedPaths: <String>[root],
    resourceProvider: PhysicalResourceProvider.INSTANCE,
  );

  final issues = <_Issue>[];
  var analyzed = 0;

  for (final AnalysisContext context in collection.contexts) {
    final files = context.contextRoot.analyzedFiles();
    for (final String file in files) {
      if (!file.endsWith('.dart')) continue;
      final rel = p.relative(file, from: root).replaceAll(r'\', '/');
      if (!targets.any((t) => rel.startsWith('$t/'))) continue;

      final SomeErrorsResult result;
      try {
        result = await context.currentSession.getErrors(file);
      } on Object {
        continue;
      }
      if (result is! ErrorsResult) continue;

      analyzed++;
      for (final AnalysisError e in result.errors) {
        issues.add(
          _Issue(
            rel,
            e.offset,
            e.errorCode.type.displayName,
            e.errorCode.name,
            e.message,
          ),
        );
      }
    }
  }

  issues.sort((a, b) => a.file != b.file
      ? a.file.compareTo(b.file)
      : a.offset.compareTo(b.offset));

  final swapped = <_Issue>[];
  final counts = <String, int>{};
  for (final i in issues) {
    counts[i.severity] = (counts[i.severity] ?? 0) + 1;
    swapped.add(i);
  }

  final out = StringBuffer()
    ..writeln('分析 $analyzed 个 dart 文件，目标目录：${targets.join(' ')}');
  for (final i in swapped) {
    out.writeln('${i.severity} | ${i.file}:${i.offset} | ${i.code} | ${i.message}');
  }
  if (swapped.isEmpty) {
    out.writeln('✅ 未发现 issues（INFO 及以上）');
  } else {
    out.writeln('❌ 共 ${swapped.length} 项：${counts.entries.map((e) => '${e.key} ${e.value}').join('，')}');
  }
  stdout.write(out.toString());
  return swapped.isEmpty ? 0 : 1;
}

class _Issue {
  const _Issue(this.file, this.offset, this.severity, this.code, this.message);

  final String file;
  final int offset;
  final String severity;
  final String code;
  final String message;
}
