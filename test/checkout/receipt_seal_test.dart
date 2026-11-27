import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/services/receipt_seal_service.dart';
import 'package:pos_app/services/receipt_service.dart';

SaleRecord sale() => SaleRecord(
  id: 'sealed',
  storeCode: 'A',
  storeName: 'Shop',
  cashierUid: 'cashier',
  cashierName: 'Cashier',
  paymentMethod: 'Cash',
  createdAt: DateTime.utc(2026, 11, 27),
  items: const [SaleLine(productId: 'pen', barcode: '123', name: 'Pen', price: 2, quantity: 1)],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<FakeFirebaseFirestore> db({String? token = 'payload.signature'}) async {
    final firestore = FakeFirebaseFirestore();
    final input = sale();
    await firestore.doc('sales/sealed').set({
      ...input.toJson(),
      'createdAt': Timestamp.fromDate(input.createdAt),
      'status': 'completed',
      'type': 'sale',
      'receiptSeal': ?token,
    });
    return firestore;
  }

  test(
    'only confirmed matching proof from the configured server creates a verification link',
    () async {
      final firestore = await db();
      final result = await ReceiptSealService.load(
        sale(),
        firestore: firestore,
        endpoint: 'https://trusted.example/api/checkout',
        httpClient: MockClient((request) async {
          expect(request.url.toString(), 'https://trusted.example/api/verify');
          expect(jsonDecode(request.body), {'token': 'payload.signature'});
          return http.Response(
            '{"valid":true,"receipt":"RCPT-sealed","currency":"BHD","totalFils":2000,"merchant":"Shop","date":"2026-11-27T00:00:00.000Z"}',
            200,
          );
        }),
      );
      expect(result, isNotNull);
      expect(result!.url.host, 'trusted.example');
      expect(result.url.queryParameters['token'], 'payload.signature');
      expect(result.sale.total, 2);
    },
  );
  test(
    'unsigned, invalid, mismatched, foreign-store or unavailable proofs never receive a seal',
    () async {
      for (final body in [
        '{"valid":false}',
        '{"valid":true,"receipt":"RCPT-sealed","currency":"BHD","totalFils":1}',
        'not json',
      ]) {
        expect(
          await ReceiptSealService.load(
            sale(),
            firestore: await db(),
            endpoint: 'https://trusted.example/checkout',
            httpClient: MockClient((_) async => http.Response(body, 200)),
          ),
          isNull,
        );
      }
      expect(
        await ReceiptSealService.load(
          sale(),
          firestore: await db(token: null),
          endpoint: 'https://trusted.example/checkout',
        ),
        isNull,
      );
      final foreign = await db();
      await foreign.doc('sales/sealed').update({'storeCode': 'B'});
      expect(
        await ReceiptSealService.load(
          sale(),
          firestore: foreign,
          endpoint: 'https://trusted.example/checkout',
        ),
        isNull,
      );
      expect(
        await ReceiptSealService.load(
          sale(),
          firestore: await db(),
          endpoint: 'https://trusted.example/checkout',
          httpClient: MockClient((_) async => http.Response('{}', 503)),
        ),
        isNull,
      );
    },
  );
  test('unconfigured or unsafe endpoints never contact a receipt verifier', () async {
    for (final endpoint in [
      '',
      'http://unsafe.example/checkout',
      'https://user:secret@trusted.example/checkout',
      'https://trusted.example/checkout?secret=x',
    ]) {
      expect(
        await ReceiptSealService.load(
          sale(),
          endpoint: endpoint,
          httpClient: MockClient((_) async => throw StateError('must not contact')),
        ),
        isNull,
      );
    }
  });
  test('signed receipt QR renders as an 80mm PDF without losing ordinary receipts', () async {
    final input = sale();
    final signed = await ReceiptService.generatePdf(
      input,
      status: 'Synchronized',
      verifiedSeal: ReceiptSealData(
        input,
        Uri.parse('https://trusted.example/verify?token=payload.signature'),
      ),
    );
    final ordinary = await ReceiptService.generatePdf(input, status: 'Saved on device');
    expect(ascii.decode(signed.take(5).toList()), '%PDF-');
    expect(ascii.decode(ordinary.take(5).toList()), '%PDF-');
    expect(signed.length, greaterThan(ordinary.length));
  });
}
