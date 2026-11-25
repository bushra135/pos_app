import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/utils/receipt_layout.dart';
import 'package:pos_app/utils/vat_invoice.dart';
import 'package:shared_preferences/shared_preferences.dart';

SaleRecord _sale({double vatRate = 10, String kind = InvoiceKind.simplified, String buyer = ''}) =>
    SaleRecord(
      id: 'abc123',
      storeCode: 'S',
      storeName: 'قرطاسية الريم',
      cashierUid: 'c1',
      cashierName: 'Noora',
      paymentMethod: 'BenefitPay',
      createdAt: DateTime(2026, 11, 25, 9, 41),
      items: const [
        SaleLine(productId: 'p1', barcode: '1', name: 'Blue pen', price: 0.5, quantity: 2),
        SaleLine(productId: 'p2', barcode: '2', name: 'Notebook A4', price: 1.85, quantity: 1),
      ],
      vatRate: vatRate,
      invoiceNumber: 'INV-KQM-000245',
      invoiceKind: kind,
      storeVatNumber: kind == InvoiceKind.receipt ? '' : '123456789012345',
      storeAddress: 'Seef Mall, Shop 12, Manama, Kingdom of Bahrain',
      buyerName: buyer,
      buyerAddress: buyer.isEmpty ? '' : 'Bldg 5, Road 12, Riffa, Bahrain',
      buyerVatNumber: buyer.isEmpty ? '' : '987654321098765',
    );

void main() {
  test('VAT applies only to registered stores; unset stores keep the old 10%', () {
    expect(StoreVat.fromStore(null).rate, 10, reason: 'not set yet');
    final registered = StoreVat.fromStore({
      'vatRegistered': true,
      'vatNumber': '123456789012345',
      'storeAddress': 'Manama',
    });
    expect(registered.rate, 10);
    expect(registered.issuesTaxInvoices, isTrue);
    final unregistered = StoreVat.fromStore({'vatRegistered': false, 'vatNumber': ''});
    expect(unregistered.rate, 0);
    expect(unregistered.issuesTaxInvoices, isFalse);
    expect(InvoiceKind.forSale(vat: unregistered, buyerDetails: true), InvoiceKind.receipt);
    expect(InvoiceKind.forSale(vat: registered, buyerDetails: false), InvoiceKind.simplified);
    expect(InvoiceKind.forSale(vat: registered, buyerDetails: true), InvoiceKind.full);
  });

  test('VAT number and address checks', () {
    expect(VatChecks.vatNumber('1234 5678 9012 345', required: true), isNull);
    expect(VatChecks.vatNumber('12345', required: true), isNotNull);
    expect(VatChecks.vatNumber('', required: true), isNotNull);
    expect(VatChecks.vatNumber('', required: false), isNull);
    expect(VatChecks.address('P.O. Box 1234', required: true), isNotNull);
    expect(VatChecks.address('ص.ب 1234', required: true), isNotNull);
    expect(VatChecks.address('Seef Mall, Shop 12, Manama, Bahrain', required: true), isNull);
    expect(VatChecks.pretty('123456789012345'), '1234 5678 9012 345');
  });

  test('invoice numbers count up per store and keep the device code', () async {
    SharedPreferences.setMockInitialValues({});
    final numbers = InvoiceNumbers(await SharedPreferences.getInstance());
    final a1 = await numbers.next('A');
    final a2 = await numbers.next('A');
    final b1 = await numbers.next('B');
    final code = numbers.deviceCode;
    expect(code, hasLength(3));
    expect(a1, 'INV-$code-000001');
    expect(a2, 'INV-$code-000002');
    expect(b1, 'INV-$code-000001');
  });

  test('simplified tax invoice carries the NBR fields', () {
    final layout = ReceiptLayout.of(_sale());
    expect(layout.title, contains('Simplified Tax Invoice'));
    expect(layout.storeLines, [
      'Seef Mall, Shop 12, Manama, Kingdom of Bahrain',
      'رقم حساب ض.ق.م · VAT No. 1234 5678 9012 345',
    ]);
    expect(layout.meta.first.value, 'INV-KQM-000245');
    final totals = {for (final r in layout.totals) r.label: r.value};
    expect(totals['ضريبة القيمة المضافة · VAT 10%'], 'BD 0.259');
    expect(totals['المبلغ قبل الضريبة · Excl. VAT'], 'BD 2.591');
    expect(totals['الإجمالي شامل الضريبة · Total incl. VAT'], 'BD 2.850');
    expect(layout.buyer, isEmpty);
  });

  test('full tax invoice adds the customer block', () {
    final layout = ReceiptLayout.of(_sale(kind: InvoiceKind.full, buyer: 'Gulf Trading W.L.L.'));
    expect(layout.title, contains('Tax Invoice'));
    expect(layout.title, isNot(contains('Simplified')));
    expect(layout.buyer.map((r) => r.value), [
      'Gulf Trading W.L.L.',
      'Bldg 5, Road 12, Riffa, Bahrain',
      '9876 5432 1098 765',
    ]);
  });

  test('a store that is not VAT-registered prints a receipt with no VAT', () {
    final layout = ReceiptLayout.of(_sale(vatRate: 0, kind: InvoiceKind.receipt));
    expect(layout.title, 'إيصال · Receipt');
    expect(layout.storeLines.any((l) => l.contains('VAT')), isFalse);
    expect(layout.totals.any((r) => r.label.contains('VAT')), isFalse);
    expect(layout.totals.firstWhere((r) => r.strong).value, 'BD 2.850');
    expect(_sale(vatRate: 0, kind: InvoiceKind.receipt).tax, 0);
  });
}
