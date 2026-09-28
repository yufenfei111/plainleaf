import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把附件以「用户看到的名字」交给系统（W20）
///
/// ## 解决的是什么
/// 盘上落的是 `media/yyyy/mm/<uuid>.pdf`（uuid 去重、避免路径注入），
/// 而列表里显示的是原始文件名「作业第三章.pdf」。直接把盘上路径交给系统应用，
/// 那么系统标题栏、"另存为"的默认名、分享出去的文件名全都是那串 uuid ——
/// 用户看到的现象是「我点的是作业第三章.pdf，怎么变成 0f3a… 了」。
///
/// 所以交出之前要**按展示名准备一份副本**。
///
/// ## 为什么不动存储层（不让盘上就按原名存）
/// 原文件名会带来三件必须处理的事：同名冲突、非法字符（`/`、`:`、`?` 在 Windows
/// 上直接写不进去）、以及"文件名可控"带来的路径穿越风险。库内用 uuid 是**对的设计**，
/// 问题只出在"交出去"这一步 —— 所以修在交出处，不去动数据层。
///
/// ## 副本放哪、会不会越攒越多
/// 放系统临时目录下的 `plainleaf-handoff/<库内文件名>/<展示名>`：
/// - **每个附件一个子目录**（用库内文件名做目录名）：两个不同记录挂着同名文件时
///   不会互相顶掉，同时**文件名本身仍是干净的展示名**。
///   给"另存为"默认名加 uuid 前缀是最省事的做法，但那恰恰违反了本方法要修的问题；
/// - 系统可随时回收临时目录；另外本类在**每次进程内首次使用时清理一次**超过 7 天的
///   旧副本（见 `_pruneOnce`），避免桌面端无限增长；
/// - 盘上文件名**已经等于展示名**时（历史数据没有 originalName，展示名回退成
///   文件名本身）直接返回原路径，**不复制**。
class AttachmentHandoff {
  AttachmentHandoff({Future<Directory> Function()? stagingRoot})
      : _stagingRoot = stagingRoot ?? _defaultStagingRoot;

  /// 可注入：测试要一个确定目录，产品走系统临时目录
  final Future<Directory> Function() _stagingRoot;

  static const String _stagingDirName = 'plainleaf-handoff';

  /// 旧副本保留期：够长到"今天开过、明天接着看"，又不至于长期占空间。
  static const Duration _maxAge = Duration(days: 7);

  /// 进程内只清理一次 —— 每次点击都遍历一遍目录是没必要的开销
  static bool _pruned = false;

  static Future<Directory> _defaultStagingRoot() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, _stagingDirName));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 返回一个**文件名等于 [displayName]** 的绝对路径，可直接交给系统应用或用于保存。
  ///
  /// 拿不到合法展示名、或盘上文件名本就一致时返回 [sourceAbsPath] 原样 ——
  /// 这条路径永远不会返回 null，调用方不必再处理"没有名字"的分支。
  Future<String> prepare({
    required String sourceAbsPath,
    required String? displayName,
  }) async {
    final source = File(sourceAbsPath);
    final wanted = safeDisplayFileName(displayName);
    // 展示名不可用，或已经与盘上文件名一致 → 不需要副本
    if (wanted == null || wanted == p.basename(sourceAbsPath)) {
      return sourceAbsPath;
    }
    // 源不在盘上：把原路径交出去，让系统去报"文件不存在"。
    // 在这里编一个更准确的错没有意义 —— 调用方也没有补救手段。
    if (!source.existsSync()) return sourceAbsPath;

    final root = await _stagingRoot();
    await _pruneOnce(root);

    final slot = Directory(
      p.join(root.path, p.basenameWithoutExtension(sourceAbsPath)),
    );
    final target = File(p.join(slot.path, wanted));
    if (!slot.existsSync()) slot.createSync(recursive: true);

    // 已有一份且大小一致 → 复用（反复点开同一个附件不该反复复制几十 MB）。
    // 大小不一致说明源被替换过，重写。
    final reusable =
        target.existsSync() && target.lengthSync() == source.lengthSync();
    if (!reusable) await source.copy(target.path);
    return target.path;
  }

  /// 清掉超过保留期的旧副本。
  ///
  /// 整体失败时静默跳过：清理只是"别越攒越多"，不该因为它失败就让
  /// "打开附件"这件事跟着失败。
  Future<void> _pruneOnce(Directory root) async {
    if (_pruned) return;
    _pruned = true;
    try {
      final deadline = DateTime.now().subtract(_maxAge);
      for (final entity in root.listSync()) {
        if (entity.statSync().modified.isBefore(deadline)) {
          entity.deleteSync(recursive: true);
        }
      }
    } on FileSystemException {
      // 忽略：下次启动还会再试
    }
  }
}

/// 展示名 → 可安全落盘的文件名；无法得到可用名字时返回 null（调用方回退原路径）。
///
/// 只做**必须做**的清理，不试图"美化"用户的名字：
/// - 取 basename 之后**再**把残留的分隔符替换掉：`p.basename('/')` 在各平台
///   上下文里并不都返回空串（可能原样返回 `/`），只靠 basename 会漏出
///   一个名叫 `/` 的文件；
/// - 替换路径非法字符与控制字符（Windows 上 `<>:"|?*` 与 0x00–0x1F 写不进去）；
/// - 去掉结尾的 `.` 与空格（Windows 会静默丢弃，导致"我明明叫这个名字"对不上）；
/// - `.` / `..` 判无效；
/// - 按 **UTF-8 字节数**截断并保留扩展名。不能按字符数截：
///   ext4 与 NTFS 的单段文件名上限都是 255，而中文一个字占 3 字节 ——
///   按 120 个字符截断在中文长标题上照样超限，届时会得到一个
///   "文件名过长"的写盘失败，比截断更难排查。
String? safeDisplayFileName(String? raw) {
  if (raw == null) return null;
  // 反斜杠先归一：host 为 posix 时 p.basename 不认 `\`，行为会随平台漂移
  var name = p.basename(raw.replaceAll('\\', '/'));
  name = name.replaceAll(RegExp(r'[<>:"|?*/\\\x00-\x1F]'), '_');
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty || name == '.' || name == '..') return null;

  const maxBytes = 200; // 留出余量（上限 255，且要算上扩展名与可能的去重后缀）
  if (utf8.encode(name).length > maxBytes) {
    final ext = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    final budget = maxBytes - utf8.encode(ext).length;
    name = budget > 0 ? '${_takeBytes(base, budget)}$ext' : _takeBytes(name, maxBytes);
    if (name.isEmpty || name == '.') return null;
  }
  return name;
}

/// 按 UTF-8 字节预算取前若干**完整字符**（不切碎多字节字符与代理对）
String _takeBytes(String text, int budget) {
  final buf = StringBuffer();
  var used = 0;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final size = utf8.encode(char).length;
    if (used + size > budget) break;
    buf.write(char);
    used += size;
  }
  return buf.toString();
}

/// 保存到磁盘时的目标文件名。
///
/// 与 [AttachmentHandoff.prepare] 同一套命名规则（都走 [safeDisplayFileName]）——
/// "打开"与"保存"两条链路各写一份清理逻辑，早晚会出现同一个附件两个名字。
///
/// 展示名不带扩展名时补上源文件的扩展名：老数据可能只存了名字没存扩展名，
/// 存成没有扩展名的文件会让系统再也认不出它是什么类型。
String targetFileNameFor(String sourcePath, String? displayName) {
  final safe = safeDisplayFileName(displayName);
  if (safe == null) return p.basename(sourcePath);
  return p.extension(safe).isEmpty ? '$safe${p.extension(sourcePath)}' : safe;
}
