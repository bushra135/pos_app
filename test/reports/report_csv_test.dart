import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/report_csv.dart';

void main() {
  test('Excel text preserves Arabic, quotes and embedded line breaks', () {
    final csv = ReportCsv.encode([
      ['قلم', 'A,"B"\nC', null],
    ]);
    expect(csv, '\ufeff"قلم","A,""B""\nC",\r\n');
  });
  test('Untrusted text cannot become a spreadsheet formula', () {
    final csv = ReportCsv.encode([
      ['=SUM(A1)', ' +123', '@test', '-text', -2.5, 3],
    ]);
    expect(csv, contains('"\'=SUM(A1)"'));
    expect(csv, contains('"\' +123"'));
    expect(csv, contains('"\'@test"'));
    expect(csv, contains('"\'-text"'));
    expect(csv, endsWith('-2.500,3\r\n'));
  });
}
