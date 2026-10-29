import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/barcode_scan_guard.dart';

void main() {
  test('A held barcode cannot repeatedly add units', () {
    final gate = BarcodeScanGuard();
    expect(gate.accept('123'), isTrue);
    for (var frame = 0; frame < 500; frame++) {
      expect(gate.accept('123'), isFalse);
    }
  });

  test('Different items scan immediately and a removed label can return', () {
    final gate = BarcodeScanGuard();
    expect(gate.accept('123'), isTrue);
    expect(gate.accept('456'), isTrue);
    expect(gate.accept('456'), isFalse);
    gate.release();
    expect(gate.accept('456'), isTrue);
    expect(gate.accept(''), isFalse);
  });
}
