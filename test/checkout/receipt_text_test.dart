import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/app_language.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/utils/receipt_text.dart';

SaleRecord _sale() => SaleRecord(
  id: 'ABC123',
  storeCode: 'S',
  storeName: 'Al Reem Stationery',
  cashierUid: 'c1',
  cashierName: 'Noora',
  paymentMethod: 'Cash',
  createdAt: DateTime(2026, 11, 25, 9, 5),
  items: const [
    SaleLine(productId: 'p1', barcode: '1', name: 'Blue pen', price: 0.5, quantity: 2),
    SaleLine(productId: 'p2', barcode: '2', name: 'Notebook A4', price: 1.75, quantity: 1),
  ],
  discount: 0.25,
  vatRate: 10,
);

void main() {
  tearDown(() => AppLanguage.locale.value = AppLanguage.english);

  test('local Bahraini numbers get 973; others are cleaned or refused', () {
    expect(ReceiptText.whatsappNumber('3300 0000'), '97333000000');
    expect(ReceiptText.whatsappNumber('+973 3300-0000'), '97333000000');
    expect(ReceiptText.whatsappNumber('0097333000000'), '97333000000');
    expect(ReceiptText.whatsappNumber('+966 50 123 4567'), '966501234567');
    expect(ReceiptText.whatsappNumber('12345'), isNull);
    expect(ReceiptText.whatsappNumber('33OO 0000'), isNull);
  });

  test('the message lists items, discount, VAT, total and payment, bilingual', () {
    final text = ReceiptText.message(_sale());
    expect(text, contains('Al Reem Stationery'));
    expect(text, contains('RCPT-ABC123'));
    expect(text, contains('Blue pen  2 × BD 0.500 = BD 1.000'));
    expect(text, contains('خصم · Discount: − BD 0.250'));
    expect(text, contains('ضريبة القيمة المضافة · VAT 10%: BD 0.227'));
    expect(text, contains('الإجمالي شامل الضريبة · Total incl. VAT: BD 2.500'));
    expect(text, contains('الدفع · Paid by: نقداً · Cash'));
  });

  test('the receipt labels are bilingual in either app language; amounts follow it', () {
    AppLanguage.locale.value = AppLanguage.arabic;
    final text = ReceiptText.message(_sale());
    expect(text, contains('الإجمالي شامل الضريبة · Total incl. VAT: 2.500 د.ب'));
    expect(text, contains('الدفع · Paid by: نقداً · Cash'));
  });

  test('the wa.me link carries the number and the receipt text', () {
    final link = ReceiptText.whatsappLink(_sale(), number: '97333000000');
    expect(link.host, 'wa.me');
    expect(link.path, '/97333000000');
    expect(link.queryParameters['text'], contains('RCPT-ABC123'));
    expect(ReceiptText.whatsappLink(_sale()).path, '/');
  });
}
