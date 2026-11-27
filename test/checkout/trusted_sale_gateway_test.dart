import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/services/sale_gateway.dart';
import 'package:pos_app/services/trusted_sale_gateway.dart';

SaleRecord receipt() => SaleRecord(
  id: 'one',
  storeCode: 'A',
  storeName: 'Store',
  cashierUid: 'cashier',
  cashierName: 'Cashier',
  paymentMethod: 'Cash',
  createdAt: DateTime.now(),
  items: const [SaleLine(productId: 'pen', barcode: '123', name: 'Pen', price: 2, quantity: 1)],
);
void main() {
  test('sends an authenticated intent and requires matching confirmation', () async {
    final gateway = TrustedSaleGateway(
      endpoint: 'https://checkout.example/checkout',
      idToken: () async => 'id-token',
      currentUserId: () => 'cashier',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer id-token');
        expect(jsonDecode(request.body)['items'][0]['price'], 2);
        return http.Response('{"id":"one","status":"completed"}', 200);
      }),
    );
    await gateway.commit(receipt());
  });
  test('unconfigured or insecure endpoints fail closed without a direct write', () async {
    for (final endpoint in [
      '',
      'http://remote.example/checkout',
      'https://user:secret@checkout.example/checkout',
      'https://checkout.example/checkout?token=secret',
    ]) {
      final gateway = TrustedSaleGateway(
        endpoint: endpoint,
        idToken: () async => 'token',
        currentUserId: () => 'cashier',
        client: MockClient((_) async => throw StateError('must not send')),
      );
      await expectLater(gateway.commit(receipt()), throwsStateError);
    }
  });
  test('wrong account and missing authentication never submit a receipt', () async {
    for (final uid in ['other', 'cashier']) {
      final gateway = TrustedSaleGateway(
        endpoint: 'https://checkout.example/checkout',
        idToken: () async => null,
        currentUserId: () => uid,
        client: MockClient((_) async => throw StateError('must not send')),
      );
      await expectLater(gateway.commit(receipt()), throwsA(isA<SaleConflictException>()));
    }
  });
  test('permission and business conflicts remain reviewable, outages are retryable', () async {
    for (final status in [400, 401, 403, 409, 503]) {
      final gateway = TrustedSaleGateway(
        endpoint: 'https://checkout.example/checkout',
        idToken: () async => 'token',
        currentUserId: () => 'cashier',
        client: MockClient(
          (_) async => http.Response('{"message":"private server detail"}', status),
        ),
      );
      try {
        await gateway.commit(receipt());
        fail('must reject');
      } catch (error) {
        expect(error.toString(), isNot(contains('private server detail')));
        if (status == 503) {
          expect(error, isA<StateError>());
        } else {
          expect(error, isA<SaleConflictException>());
        }
      }
    }
  });
  test('unconfirmed, malformed and mismatched responses cannot clear a pending sale', () async {
    for (final body in [
      'not json',
      '{"id":"other","status":"completed"}',
      '{"id":"one","status":"queued"}',
    ]) {
      final gateway = TrustedSaleGateway(
        endpoint: 'https://checkout.example/checkout',
        idToken: () async => 'token',
        currentUserId: () => 'cashier',
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(gateway.commit(receipt()), throwsA(anything));
    }
  });
  test('account switch during confirmation does not confirm for the new session', () async {
    var uid = 'cashier';
    final gateway = TrustedSaleGateway(
      endpoint: 'https://checkout.example/checkout',
      idToken: () async => 'token',
      currentUserId: () => uid,
      client: MockClient((_) async {
        uid = 'other';
        return http.Response('{"id":"one","status":"completed"}', 200);
      }),
    );
    await expectLater(gateway.commit(receipt()), throwsA(isA<SaleConflictException>()));
  });
}
