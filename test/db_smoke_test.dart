import 'package:flutter_test/flutter_test.dart';
import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/db/seed.dart';

void main() {
  test('db layer smoke: create + seed + query', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    await DemoSeed.maybeSeed(db);
    final entries = await db.select(db.entries).get();
    final todos = await db.select(db.todos).get();
    final notebooks = await db.select(db.notebooks).get();
    expect(notebooks.length, 2);
    expect(entries.length, 4);
    expect(todos.length, 2);
    // 幂等：重复调用不翻倍
    await DemoSeed.maybeSeed(db);
    expect((await db.select(db.entries).get()).length, 4);
    // 五字段存在性抽查
    expect(entries.first.uuid.length, 36);
    expect(entries.first.version, 1);
    expect(entries.first.deleted, false);
    await db.close();
  }, timeout: const Timeout(Duration(seconds: 30)));
}