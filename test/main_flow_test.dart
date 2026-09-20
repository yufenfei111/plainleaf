import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/exporter/backup_service.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// 主链路集成测试（DEVELOPMENT.md §5.3）：
/// 建记录 → FTS 搜得到 → 导出 .plbk → 恢复 → 数据一致（含 FTS 仍可检索）。
///
/// 说明：放在 test/ 而非 integration_test/，因为后者需要真机/模拟器才能执行，
/// 无法纳入本机与 CI 的 `flutter test`；本例走真实文件库，覆盖度等价。
final _root = Directory.systemTemp.createTempSync('plainleaf_flow');

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePaths(_root.path);
  });

  test('建记录 → 搜得到 → 备份 → 恢复 → 数据一致', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    final repo = LocalTimelineRepository(db.entriesDao);

    // 1) 建记录
    final id = await repo.saveEntry(
      const EntryDraft(title: '主链路验收', plainText: '内容甲乙丙'),
    );

    // 2) FTS 搜得到（中文需前缀化）
    expect(await db.entriesDao.searchEntryIds('主链路*'), contains(id));

    // 3) 导出备份包
    final service = BackupService(db);
    final plbk = await service.exportBackup(fileName: 'flow.plbk');
    expect(plbk.existsSync(), isTrue);
    expect((await service.verify(plbk))['entries'], greaterThanOrEqualTo(1));

    // 4) 恢复（内部先自动备份当前数据，再关库替换；此后 db 不可用）
    final restoredPath = await service.restore(plbk);

    // 5) 用恢复后的库文件重新打开，校验数据与全文索引
    final db2 = PlainLeafDatabase.forTesting(NativeDatabase(restoredPath));
    addTearDown(db2.close);

    final rows = await db2.select(db2.entries).get();
    expect(rows.any((e) => e.title == '主链路验收'), isTrue,
        reason: '恢复后记录应保留');
    expect(await db2.entriesDao.searchEntryIds('主链路*'), isNotEmpty,
        reason: '恢复后 FTS 索引仍可用');

    // 数据红线：恢复前自动备份了一份
    final safety = await service.listBackups();
    expect(safety.any((b) => b.fileName.contains('before-restore')), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
