import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/report_workbook.dart';

void main() {
  test(
    'compact references are repeatable and preserve identity independently of sorting',
    () {
      final first = ReportWorkbook.reference(
        'INV',
        'a-long-internal-receipt-id',
      );
      expect(first, matches(RegExp(r'^INV-[0-9A-F]{10}$')));
      expect(
        ReportWorkbook.reference('INV', 'a-long-internal-receipt-id'),
        first,
      );
      expect(ReportWorkbook.reference('INV', 'another-receipt'), isNot(first));
      expect(
        ReportWorkbook.reference('CS', 'a-long-internal-receipt-id'),
        startsWith('CS-'),
      );
      expect(ReportWorkbook.reference('CS', ''), 'Not recorded');
    },
  );
  test(
    'real Excel ZIP preserves Arabic, text identifiers, numbers and formatting',
    () {
      final bytes = ReportWorkbook.encode([
        ['Receipt', 'Item', 'Amount', 'Units'],
        ['00123', 'قلم & <Blue>\nSecond line', 3.125, 2],
        ['=SUM(A1)', '@name', -2.5, 0],
      ]);
      expect(bytes.take(2), [0x50, 0x4b]);
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final sheet = utf8.decode(
        archive.findFile('xl/worksheets/sheet1.xml')!.content,
      );
      expect(sheet, contains('قلم &amp; &lt;Blue&gt;'));
      expect(
        sheet,
        contains('t="inlineStr"><is><t xml:space="preserve">00123'),
      );
      expect(sheet, contains('=SUM(A1)'));
      expect(sheet, isNot(contains('<f>')));
      expect(sheet, contains('<c r="C2" s="2"><v>3.125</v></c>'));
      expect(sheet, contains('<c r="D2" s="3"><v>2</v></c>'));
      expect(sheet, contains('state="frozen"'));
      expect(sheet, contains('<autoFilter ref="A1:D3"/>'));
      expect(
        utf8.decode(archive.findFile('xl/styles.xml')!.content),
        contains('#,##0.000'),
      );
      expect(archive.findFile('[Content_Types].xml'), isNotNull);
      expect(archive.findFile('xl/_rels/workbook.xml.rels'), isNotNull);
    },
  );
  test('column addresses extend past Z and invalid shapes are rejected', () {
    final archive = ZipDecoder().decodeBytes(
      ReportWorkbook.encode([
        List<Object?>.generate(28, (index) => 'Column $index'),
      ]),
    );
    final sheet = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content,
    );
    expect(sheet, contains('r="AB1"'));
    expect(() => ReportWorkbook.encode([]), throwsArgumentError);
    expect(
      () => ReportWorkbook.encode([
        ['A'],
        ['B', 'C'],
      ]),
      throwsArgumentError,
    );
  });
}
