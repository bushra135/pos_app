import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/product_import.dart';

void main() {
  test('rows pasted from Excel are parsed, with the header row skipped', () {
    final result = ProductImport.parse(
      'Barcode\tName\tCategory\tPrice\tStock\tCost\n'
      '6281000000011\tBlue pen\tStationery\t0.500\t40\t0.300\n'
      '6281000000028\tNotebook A4\tStationery\t1.850\t12\n',
    );
    expect(result.errors, isEmpty);
    expect(result.ready, hasLength(2));
    final pen = result.ready.first;
    expect(pen.barcode, '6281000000011');
    expect(pen.price, 0.5);
    expect(pen.stock, 40);
    expect(pen.cost, 0.3);
    expect(result.ready.last.cost, isNull);
  });

  test('CSV with commas or semicolons and decimal commas also work', () {
    final result = ProductImport.parse('111,Glue,,2.0,5\n222;Tape;Office;0,750;3');
    expect(result.errors, isEmpty);
    expect(result.ready.map((r) => r.price), [2.0, 0.75]);
    expect(result.ready.first.category, 'General');
  });

  test('barcodes already in the store or repeated in the paste are skipped', () {
    final result = ProductImport.parse(
      '111\tGlue\tOffice\t2\t5\n222\tTape\tOffice\t1\t3\n222\tTape again\tOffice\t1\t3',
      existingBarcodes: {'111'},
    );
    expect(result.ready.map((r) => r.barcode), ['222']);
    expect(result.duplicates, ['111', '222']);
  });

  test('bad rows are reported with their row number and reason', () {
    final result = ProductImport.parse(
      '111\tGlue\tOffice\t2\t5\n'
      '\tNo barcode\tOffice\t1\t1\n'
      '333\tBad price\tOffice\tabc\t1\n'
      '444\tBad stock\tOffice\t1\t-2\n'
      '555\tShort row\n',
    );
    expect(result.ready, hasLength(1));
    expect(result.errors.map((e) => e.line), [2, 3, 4, 5]);
    expect(result.errors[1].reason, contains('Price'));
    expect(result.errors[2].reason, contains('Stock'));
  });
}
