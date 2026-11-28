import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/services/local_pos_store.dart';
import 'package:pos_app/services/sale_gateway.dart';
import 'package:pos_app/services/trusted_sale_gateway.dart';
import 'package:sembast/sembast_io.dart';

/// Explicit emulator acceptance suite; run through run_checkout_emulators.cjs.
/// Kept outside test/ because it requires dedicated Auth/Firestore processes.
void main() {
  final endpoint = Platform.environment['SHOPPAD_BRIDGE_ENDPOINT'] ?? '';
  final cashierToken = Platform.environment['SHOPPAD_BRIDGE_CASHIER_TOKEN'] ?? '';
  final ownerToken = Platform.environment['SHOPPAD_BRIDGE_OWNER_TOKEN'] ?? '';
  final client = http.Client();
  late Directory directory;
  late LocalPosStore store;

  SaleRecord sale(String id, {String uid = 'bridge-cashier', double price = 2}) => SaleRecord(
    id: id,
    storeCode: 'BRIDGE',
    storeName: 'متجر التجربة',
    cashierUid: uid,
    cashierName: uid,
    paymentMethod: 'Cash',
    createdAt: DateTime.now().toUtc(),
    items: [
      SaleLine(
        productId: 'bridge-pen',
        barcode: '12345678',
        name: 'قلم Pen',
        price: price,
        quantity: 1,
      ),
    ],
  );
  TrustedSaleGateway gateway({
    String uid = 'bridge-cashier',
    String? token,
    http.Client? transport,
  }) => TrustedSaleGateway(
    endpoint: endpoint,
    client: transport ?? client,
    currentUserId: () => uid,
    idToken: () async => token ?? (uid == 'bridge-owner' ? ownerToken : cashierToken),
  );
  Future<http.Response> document(String path) => client.get(
    Uri.parse(
      'http://127.0.0.1:9184/v1/projects/demo-shoppad-security/databases/(default)/documents/$path',
    ),
    headers: {'Authorization': 'Bearer $cashierToken'},
  );
  Future<int> stock() async {
    final response = await document('products/bridge-pen');
    expect(response.statusCode, 200);
    return int.parse(jsonDecode(response.body)['fields']['stock']['integerValue']);
  }

  setUpAll(() async {
    expect(Uri.parse(endpoint).host, '127.0.0.1');
    expect(Uri.parse(endpoint).scheme, 'http');
    expect(Platform.environment['FIRESTORE_EMULATOR_HOST'], '127.0.0.1:9184');
    expect(Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'], '127.0.0.1:9197');
    expect(cashierToken, isNotEmpty);
    expect(ownerToken, isNotEmpty);
    directory = await Directory.systemTemp.createTemp('shoppad-emulator-queue-');
    store = LocalPosStore(await databaseFactoryIo.openDatabase('${directory.path}/receipts.db'));
  });
  tearDownAll(() async {
    client.close();
    await store.database.close();
    await directory.delete(recursive: true);
  });

  test('cashier queue survives reopen, confirms through real server and retries once', () async {
    final receipt = sale('bridge-cashier-sale');
    await store.enqueue(receipt);
    await store.database.close();
    store = LocalPosStore(await databaseFactoryIo.openDatabase('${directory.path}/receipts.db'));
    final pending = await store.pendingSales('bridge-cashier', 'BRIDGE');
    expect(pending.single.sale.id, receipt.id);
    await gateway().commit(pending.single.sale);
    await gateway().commit(pending.single.sale);
    final saved = await document('sales/${receipt.id}');
    expect(saved.statusCode, 200);
    final fields = jsonDecode(saved.body)['fields'];
    expect(fields['status']['stringValue'], 'completed');
    expect(fields['cashierUid']['stringValue'], 'bridge-cashier');
    expect(fields['storeName']['stringValue'], 'متجر التجربة');
    expect(await stock(), 9);
    final verification = await client.post(
      Uri.parse(endpoint.replaceFirst('/checkout', '/verify')),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': fields['receiptSeal']['stringValue']}),
    );
    expect(verification.statusCode, 200);
    expect(jsonDecode(verification.body)['valid'], true);
    expect(jsonDecode(verification.body)['totalFils'], 2000);
    await store.remove(receipt.id);
    expect(await store.pendingSales('bridge-cashier', 'BRIDGE'), isEmpty);
  });

  test('the owner can sell through the same trusted path', () async {
    await gateway(uid: 'bridge-owner').commit(sale('bridge-owner-sale', uid: 'bridge-owner'));
    expect(await stock(), 8);
  });

  test('a changed unit price cannot create a receipt or alter stock', () async {
    final receipt = sale('bridge-underpriced', price: 0.01);
    await store.enqueue(receipt);
    await expectLater(gateway().commit(receipt), throwsA(isA<SaleConflictException>()));
    expect((await document('sales/${receipt.id}')).statusCode, 404);
    expect(await stock(), 8);
    expect((await store.pendingSales('bridge-cashier', 'BRIDGE')).single.sale.id, receipt.id);
    await store.remove(receipt.id);
  });

  test('lost acknowledgement leaves a durable receipt and retry does not sell twice', () async {
    final receipt = sale('bridge-lost-ack');
    await store.enqueue(receipt);
    await expectLater(
      gateway(transport: _LoseAcknowledgement(client)).commit(receipt),
      throwsA(isA<http.ClientException>()),
    );
    expect(await stock(), 7);
    expect((await store.pendingSales('bridge-cashier', 'BRIDGE')).single.sale.id, receipt.id);
    await gateway().commit(receipt);
    expect(await stock(), 7);
    await store.remove(receipt.id);
    expect(await store.pendingSales('bridge-cashier', 'BRIDGE'), isEmpty);
  });

  test('forged authentication cannot save a sale', () async {
    final receipt = sale('bridge-forged');
    await expectLater(
      gateway(token: 'forged').commit(receipt),
      throwsA(isA<SaleConflictException>()),
    );
    expect((await document('sales/${receipt.id}')).statusCode, 404);
    expect(await stock(), 7);
  });
}

/// The actual server accepts the request, then its acknowledgement is lost.
class _LoseAcknowledgement extends http.BaseClient {
  _LoseAcknowledgement(this.inner);
  final http.Client inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    await response.stream.drain<void>();
    throw http.ClientException('Simulated lost acknowledgement');
  }
}
