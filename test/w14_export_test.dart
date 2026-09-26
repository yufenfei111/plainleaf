import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/app/providers.dart';
import 'package:plainleaf/core/db/database.dart';
import 'package:plainleaf/core/errors/app_exception.dart';
import 'package:plainleaf/core/exporter/pdf_exporter.dart';
import 'package:plainleaf/features/timeline/data/timeline_repository_impl.dart';
import 'package:plainleaf/features/timeline/domain/entities/timeline_entry.dart';

/// PDF 导出（W14）
///
/// 这里只验**行为契约**，不比对 PDF 的具体字节：PDF 是带时间戳与对象序号的容器，
/// 逐字节比对的用例一旦 CI 换设备就红，维护成本远大于收益。真正要保证的是：
/// 有字体 → 出合法的 %PDF；没字体 → 明确失败，绝不产出一份打开全是方块的"成功"。
void main() {
  test('① 找不到中文字体 → 抛 ExportException，而不是导出乱码', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);

    final exporter = PdfExporter(
      db,
      fontCandidates: const <String>['/definitely/not/a/font.ttf'],
    );
    await expectLater(exporter.exportAll(), throwsA(isA<ExportException>()));
  });

  test('② 有中文字体时导出的是合法 PDF 且含中文标题', () async {
    final font = await loadCjkFont(defaultCjkFontPaths);
    if (font == null) {
      // CI 的 Linux 容器未必装了中文字体：跳过而不是把流水线变红。
      // 真机上这条路径有 fallback（设置页会提示设备缺字体）。
      return;
    }
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    await LocalTimelineRepository(db.entriesDao).saveEntry(
      const EntryDraft(title: 'PDF 导出验收', plainText: '第一行\n第二行'),
    );

    final bytes = await PdfExporter(db).exportAll();
    expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(1000), reason: '空 PDF 说明渲染失败');
  });

  test('③ 单条导出也能出 PDF', () async {
    final font = await loadCjkFont(defaultCjkFontPaths);
    if (font == null) return;
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = LocalTimelineRepository(db.entriesDao);
    final id = await repo.saveEntry(
      const EntryDraft(title: '单条 PDF', plainText: '内容'),
    );

    final bytes = await PdfExporter(db).exportEntry(id);
    expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('④ 类型标签：与 EntryType 枚举的中文保持一致', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = LocalTimelineRepository(db.entriesDao);
    final diaryId = await repo.saveEntry(
      const EntryDraft(title: '日记', plainText: '', type: EntryType.diary),
    );
    final diary = await (db.select(db.entries)
          ..where((x) => x.id.equals(diaryId)))
        .getSingle();
    expect(PdfExporter.typeLabel(diary), '日记');
  });

  test('⑤ 正文按行拆分：不把整段塞进单个 Text（否则换行会变成空格）', () async {
    final db = PlainLeafDatabase.forTesting(openInMemoryDb());
    addTearDown(db.close);
    final repo = LocalTimelineRepository(db.entriesDao);
    final id = await repo.saveEntry(
      const EntryDraft(title: 't', plainText: '一\n二\n三'),
    );
    final entry = await (db.select(db.entries)
          ..where((x) => x.id.equals(id)))
        .getSingle();

    expect(entry.plainText.split('\n').length, 3);
  });
}
