import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/sale_record.dart';

class ReceiptSealData {
  const ReceiptSealData(this.sale, this.url);
  final SaleRecord sale;
  final Uri url;
}

/// Only a server-confirmed receipt with a verified signature receives a seal.
abstract final class ReceiptSealService {
  static Future<ReceiptSealData?> load(
    SaleRecord sale, {
    FirebaseFirestore? firestore,
    http.Client? httpClient,
    String endpoint = const String.fromEnvironment('SHOPPAD_CHECKOUT_URL'),
  }) async {
    final checkout = Uri.tryParse(endpoint);
    if (checkout == null ||
        checkout.scheme != 'https' ||
        checkout.host.isEmpty ||
        checkout.userInfo.isNotEmpty ||
        checkout.hasQuery ||
        checkout.hasFragment ||
        !checkout.path.endsWith('/checkout')) {
      return null;
    }
    final verify = checkout.replace(
      path: checkout.path.replaceFirst(RegExp(r'/checkout$'), '/verify'),
    );
    final client = httpClient ?? http.Client();
    try {
      final doc = await (firestore ?? FirebaseFirestore.instance)
          .collection('sales')
          .doc(sale.id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      final data = doc.data();
      final token = data?['receiptSeal'];
      if (data == null ||
          data['id'] != sale.id ||
          data['storeCode'] != sale.storeCode ||
          data['status'] != 'completed' ||
          data['type'] != 'sale' ||
          token is! String ||
          token.length > 4096 ||
          !RegExp(r'^[-A-Za-z0-9_]+\.[-A-Za-z0-9_]+$').hasMatch(token) ||
          data['createdAt'] is! Timestamp) {
        return null;
      }
      final canonical = SaleRecord.fromJson({
        ...data,
        'createdAt': (data['createdAt'] as Timestamp).toDate().toUtc().toIso8601String(),
      });
      final response = await client
          .post(
            verify,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final result = jsonDecode(response.body);
      if (result is! Map ||
          result['valid'] != true ||
          result['receipt'] != canonical.receiptNumber ||
          result['currency'] != 'BHD' ||
          result['merchant'] != canonical.storeName ||
          DateTime.tryParse(
                result['date'] is String ? result['date'] as String : '',
              )?.isAtSameMomentAs(canonical.createdAt) !=
              true ||
          result['totalFils'] != (canonical.total * 1000).round()) {
        return null;
      }
      return ReceiptSealData(canonical, verify.replace(queryParameters: {'token': token}));
    } catch (_) {
      // An outage must not mark a receipt as authentic or block ordinary printing.
      return null;
    } finally {
      if (httpClient == null) client.close();
    }
  }
}
