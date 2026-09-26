import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/exporter/backup_service.dart';
import '../../../core/exporter/markdown_exporter.dart';
import '../../../core/sync/webdav_client.dart';
import '../../../core/sync/webdav_config.dart';
import '../../timeline/presentation/providers/timeline_providers.dart';
import 'providers/webdav_providers.dart';

/// 我的 Tab（W5：备份与导出真实功能上线；W13 云备份（WebDAV 单向）已上线；
/// 应用锁按 W14 排期）
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          // 外观分组（W9 主题系统）：主题模式 / 字体缩放 / 强调色。
          // 放在备份分组之前，作为高频设置入口更顺手。
          _appearanceCard(context, ref),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('导出备份包（.plbk）'),
            subtitle: const Text('数据库快照 + 图片附件，可整体恢复'),
            onTap: () => _exportBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('从备份包恢复（.plbk）'),
            subtitle: const Text('覆盖当前数据，恢复前自动备份'),
            onTap: () => _restoreBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.notes_outlined),
            title: const Text('导出全部记录（Markdown）'),
            subtitle: const Text('已发布记录导出为单个 .md 文本'),
            onTap: () => _exportMarkdown(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导入 Markdown（.md）'),
            subtitle: const Text('把外部 Markdown 文本转成记录'),
            onTap: () => context.push('/import'),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('补齐历史缩略图'),
            subtitle: const Text('为早期记录重新生成缩略图，列表滑动更流畅'),
            onTap: () => _backfillThumbs(context, ref),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('全文搜索'),
            subtitle: const Text('FTS5 标题与正文检索'),
            onTap: () => _goSearch(context),
          ),
          const Divider(),
          _cloudBackupCard(context, ref),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('应用锁'),
            subtitle: const Text('W14 上线'),
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于素页'),
            // 版本号必须与 pubspec.yaml 的 version 同步手改。
            // 之前长期停在 v0.1.0，加上 versionCode 也一直是 1，
            // 导致"新包装上去看不出变化"——用户没有任何可判断的版本标识。
            subtitle: const Text('本地优先的图文记录工具 · v0.2.0（M2）'),
          ),
        ],
      ),
    );
  }

  /// 外观分组卡片（W9）：把主题模式 / 字体缩放 / 强调色收在一张卡里，
  /// 就近在设置页完成，不另开页面。卡片内所有文字/边框/选中标记都取自 Theme，
  /// 只有强调色色块本身用预设色（那是它的职责）。
  Widget _appearanceCard(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('外观', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('主题与字号仅作用于本 App；强调色会随备份一起保存',
                style: textTheme.bodySmall),
            const SizedBox(height: 16),
            _themeModeSection(context, ref),
            const SizedBox(height: 20),
            _textScaleSection(context, ref),
            const SizedBox(height: 20),
            _accentSection(context, ref),
          ],
        ),
      ),
    );
  }

  /// 主题模式：三选一。SegmentedButton 的选中态比 RadioListTile 更紧凑直观。
  Widget _themeModeSection(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('主题模式', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          selected: {mode},
          onSelectionChanged: (selection) async {
            // 改动立即写库并生效（main.dart 已接好线：Provider 一变整 App 跟着变）
            await ref.read(themeModeProvider.notifier).set(selection.single);
          },
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
            ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
            ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
          ],
        ),
        const SizedBox(height: 6),
        Text('深色模式更省电；跟随系统会按设备外观设置自动切换',
            style: textTheme.bodySmall),
      ],
    );
  }

  /// 字体缩放：从 TextScaleController.options 四档里选，标签用口语档位
  /// （更小/标准/较大/超大）而非原始数字，避免暴露 0.85 这种实现细节。
  Widget _textScaleSection(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(textScaleProvider);
    final textTheme = Theme.of(context).textTheme;
    final labels = <double, String>{
      0.85: '更小',
      1.0: '标准',
      1.15: '较大',
      1.3: '超大',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('字体缩放', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          selected: {scale},
          onSelectionChanged: (selection) async {
            await ref.read(textScaleProvider.notifier).set(selection.single);
          },
          segments: [
            for (final option in TextScaleController.options)
              ButtonSegment(
                value: option,
                label: Text(labels[option] ?? '${option * 100}%'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('仅调整本 App 内文字大小，不影响系统与其他应用',
            style: textTheme.bodySmall),
      ],
    );
  }

  /// 强调色：横向排列五个预设色块，点击切换；选中态用主题主色描边
  /// + 主题表面色底的小对勾标记（均取自 Theme，不写死）。
  Widget _accentSection(BuildContext context, WidgetRef ref) {
    final current = ref.watch(accentSeedProvider);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('强调色', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final preset in AppTheme.accents)
              _accentSwatch(
                context: context,
                preset: preset,
                selected: preset.color.toARGB32() == current,
                onTap: () async {
                  await ref
                      .read(accentSeedProvider.notifier)
                      .set(preset.color.toARGB32());
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('强调色用于按钮、选中态等主色点缀', style: textTheme.bodySmall),
      ],
    );
  }

  /// 单个强调色色块。色块本体用预设色（这是它的职责），但选中描边与对勾标记
  /// 一律取自 Theme，保证浅色/深色下都清晰可见、不写死颜色。
  Widget _accentSwatch({
    required BuildContext context,
    required AccentPreset preset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: preset.name,
      child: InkWell(
        key: Key('accent-${preset.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: ShapeDecoration(
                color: preset.color,
                shape: CircleBorder(
                  side: selected
                      ? BorderSide(color: scheme.primary, width: 3)
                      : const BorderSide(color: Colors.transparent),
                ),
              ),
            ),
            if (selected)
              // 对勾标记：底色用主题表面色、勾用主题主色，二者都取自 Theme
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: scheme.surface,
                  shape: const CircleBorder(),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(Icons.check, size: 14, color: scheme.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 云备份卡片（W13：WebDAV 单向备份上传/恢复）
  ///
  /// 取代原先那块 disabled 的占位入口。未配置时只放开「配置」按钮——
  /// 让用户在没填地址的情况下点到必然失败的操作，是纯负体验。
  ///
  /// 配置用 FutureProvider 读，但**不用 `AsyncValue.when`**：
  /// 这里是「点一下做一件事」的一次性动作，不是随数据变化的列表流，
  /// 走 when 会在重载时把上一次的操作结果冲掉（`valueOrNull` 更合适）。
  Widget _cloudBackupCard(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final config = ref.watch(webdavConfigProvider).valueOrNull;
    final status = ref.watch(cloudBackupStatusProvider);
    // Material 3 按钮默认高 40，这里补到 44 满足触控尺寸下限
    final outlineStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 44),
    );
    final filledStyle = FilledButton.styleFrom(
      minimumSize: const Size(48, 44),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('云备份（WebDAV）', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              config == null
                  ? '未配置。填写服务器地址后，可把备份包上传到你自己的网盘'
                  : '已配置 ${config.displayHost}（单向：只上传与恢复，不做双向同步）',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: outlineStyle,
                  onPressed: () => _editWebDavConfig(context, ref, config),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(config == null ? '配置' : '修改配置'),
                ),
                OutlinedButton.icon(
                  style: outlineStyle,
                  onPressed: config == null || status.isBusy
                      ? null
                      : () => ref
                          .read(cloudBackupActionsProvider)
                          .testConnection(config),
                  icon: const Icon(Icons.wifi_tethering_outlined),
                  label: const Text('测试连接'),
                ),
                FilledButton.icon(
                  style: filledStyle,
                  onPressed: config == null || status.isBusy
                      ? null
                      : () => _uploadBackup(context, ref, config),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('立即上传'),
                ),
                OutlinedButton.icon(
                  style: outlineStyle,
                  onPressed: config == null || status.isBusy
                      ? null
                      : () => _restoreFromCloud(context, ref, config),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('从云端恢复'),
                ),
              ],
            ),
            if (status.kind != CloudBackupStatusKind.idle) ...[
              const SizedBox(height: 12),
              // 只有「进行中」才画进度条：它是循环动画，常驻会拖住测试框架
              if (status.isBusy) const LinearProgressIndicator(),
              if (status.message != null) ...[
                const SizedBox(height: 8),
                Text(
                  status.message!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: status.kind == CloudBackupStatusKind.failure
                        ? scheme.error
                        : null,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 填写/修改 WebDAV 配置。
  /// 对话框一律用**它自己的 context 收尾**——用页面级 context.pop() 会把整页弹掉。
  Future<void> _editWebDavConfig(
    BuildContext context,
    WidgetRef ref,
    WebDavConfig? current,
  ) async {
    final urlController = TextEditingController(text: current?.baseUrl ?? '');
    final userController = TextEditingController(text: current?.username ?? '');
    final passController = TextEditingController(text: current?.password ?? '');
    WebDavConfig? edited;
    try {
      edited = await showDialog<WebDavConfig>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('配置 WebDAV'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://dav.example.com/dav/素页备份/',
                  ),
                ),
                TextField(
                  controller: userController,
                  decoration: const InputDecoration(labelText: '账号'),
                ),
                TextField(
                  controller: passController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码 / 应用密码'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                WebDavConfig(
                  baseUrl: urlController.text.trim(),
                  username: userController.text.trim(),
                  password: passController.text,
                ),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      // 对话框关闭后控制器就没用了，必须释放（否则每次点配置都漏三个）
      urlController.dispose();
      userController.dispose();
      passController.dispose();
    }
    if (edited == null || !context.mounted) return;
    await ref.read(cloudBackupActionsProvider).saveConfig(edited);
  }

  Future<void> _uploadBackup(
    BuildContext context,
    WidgetRef ref,
    WebDavConfig config,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(cloudBackupActionsProvider).upload(config);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
        result == null
            ? '上传失败，请看卡片上的提示'
            : '已上传 ${result.remoteName}（${_formatSize(result.sizeBytes)}）',
      ),
      duration: const Duration(seconds: 4),
    ));
  }

  /// 从云端恢复：列远端 .plbk → 选择 → 二次确认 → 落地。
  /// 落地前的自动备份由 BackupService.restore 负责（数据红线），这里不重复做。
  Future<void> _restoreFromCloud(
    BuildContext context,
    WidgetRef ref,
    WebDavConfig config,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final items = await ref.read(cloudBackupActionsProvider).listRemote(config);
    if (!context.mounted) return;

    if (items == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('获取云端备份失败，请看卡片上的提示')),
      );
      return;
    }
    if (items.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('云端还没有备份包，请先上传一次')),
      );
      return;
    }

    final picked = await showModalBottomSheet<WebDavResource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择要恢复的云端备份')),
            for (final item in items)
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: Text(item.name),
                subtitle: Text(_describeRemote(item)),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认恢复？'),
        content: const Text(
          '云端备份将整体覆盖当前数据。恢复前会自动再备份一次现有数据，'
          '完成后需重启应用加载新数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final file = await ref.read(cloudBackupActionsProvider).restore(config, picked);
    if (!context.mounted) return;
    if (file == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('恢复失败，请看卡片上的提示')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复完成'),
        content: const Text('数据已替换，请完全退出并重启应用以加载新数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  String _describeRemote(WebDavResource item) {
    final size = _formatSize(item.sizeBytes ?? 0);
    final when = item.modifiedAt;
    return when == null ? size : '${_formatTime(when)} · $size';
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('正在打包备份…'), duration: Duration(seconds: 2)),
    );
    try {
      final service = BackupService(ref.read(dbProvider));
      final file = await service.exportBackup();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text('备份完成：${file.path.split(r'\').last}'),
        duration: const Duration(seconds: 4),
      ));
    } on Exception catch (error) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('备份失败：$error')));
    }
  }

  /// 导出全部记录为 Markdown（W10 修复：此前只把内容 print 到控制台，
  /// 用户在 App 里点了「导出」却拿不到任何文件——功能等于没做完。
  /// 现在落到 App 私有目录的 export/ 下，并在提示里给出完整路径。）
  Future<void> _exportMarkdown(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final exporter = MarkdownExporter(ref.read(dbProvider));
      final md = await exporter.exportAll();
      final dir = await ref.read(mediaStorageProvider).supportDir();
      final exportDir = Directory(p.join(dir.path, 'export'));
      if (!exportDir.existsSync()) exportDir.createSync(recursive: true);
      final file = File(p.join(exportDir.path, _exportFileName()));
      await file.writeAsString(md, flush: true);

      final lineCount = md.split('\n').length;
      messenger.showSnackBar(SnackBar(
        content: Text('已导出 $lineCount 行：${file.path}'),
        duration: const Duration(seconds: 6),
      ));
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }

  /// 导出文件名：素页导出-20260922-2215.md（避免同名覆盖历史导出）
  String _exportFileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '素页导出-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.md';
  }

  /// 补齐历史缩略图（W6 遗留 entry：`backfillDerived` 已就绪但此前没有入口，
  /// W4 期的图永远没有 thumb，列表只能回退原图解码——滑动手感回不去）
  Future<void> _backfillThumbs(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在补齐缩略图…')));
    try {
      final n = await ref.read(timelineActionsProvider).backfillDerived();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(n == 0 ? '没有需要补齐的图片' : '已补齐 $n 张缩略图'),
        duration: const Duration(seconds: 3),
      ));
    } on Exception catch (error) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('补齐失败：$error')));
    }
  }

  /// 恢复（issue #13 闭环）：列本地 .plbk → 二次确认 → 覆盖 → 提示重启。
  /// 数据红线：restore 内部会先自动备份当前数据，再关库替换。
  Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = BackupService(ref.read(dbProvider));
      final backups = await service.listBackups();
      if (!context.mounted) return;
      if (backups.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('还没有备份包，请先导出一次')),
        );
        return;
      }

      final picked = await showModalBottomSheet<File>(
        context: context,
        builder: (_) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('选择要恢复的备份包')),
              for (final b in backups)
                ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(b.fileName),
                  subtitle: Text(
                      '${_formatTime(b.modifiedAt)} · ${_formatSize(b.sizeBytes)}'),
                  onTap: () => Navigator.pop(context, b.file),
                ),
            ],
          ),
        ),
      );
      if (picked == null || !context.mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('确认恢复？'),
          content: const Text(
            '当前数据将被该备份包整体覆盖。恢复前会自动再备份一次现有数据，'
            '完成后需重启应用加载新数据。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;

      await service.restore(picked);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('恢复完成'),
          content: const Text('数据已替换，请完全退出并重启应用以加载新数据。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('恢复失败：$error')));
    }
  }

  void _goSearch(BuildContext context) {
    context.push('/search');
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}