import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/sale_record.dart';
import 'sale_gateway.dart';

/// The device queues receipts; only the trusted server may confirm and deduct stock.
class TrustedSaleGateway implements SaleGateway {
  TrustedSaleGateway({
    http.Client? client,
    String? endpoint,
    Future<String?> Function()? idToken,
    String? Function()? currentUserId,
  }) : _client = client ?? http.Client(),
       _endpoint = endpoint ?? const String.fromEnvironment('SHOPPAD_CHECKOUT_URL'),
       _idToken =
           idToken ?? (() => FirebaseAuth.instance.currentUser?.getIdToken() ?? Future.value(null)),
       _currentUserId = currentUserId ?? (() => FirebaseAuth.instance.currentUser?.uid);

  final http.Client _client;
  final String _endpoint;
  final Future<String?> Function() _idToken;
  final String? Function() _currentUserId;

  @override
  Future<void> commit(SaleRecord sale) async {
    final uri = Uri.tryParse(_endpoint);
    final local =
        !kReleaseMode && uri != null && ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !(local && uri.scheme == 'http')) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      // No fallback to a direct client write: that would reopen the pricing bypass.
      throw StateError(
        'Secure checkout is not configured. Your receipt remains saved on this device.',
      );
    }
    if (_currentUserId() != sale.cashierUid) {
      throw const SaleConflictException('Sign in as the cashier for this sale.');
    }
    final token = await _idToken();
    if (token == null || _currentUserId() != sale.cashierUid) {
      throw const SaleConflictException('Sign in as the cashier for this sale.');
    }
    final response = await _client
        .post(
          uri,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode(sale.toJson()),
        )
        .timeout(const Duration(seconds: 20));
    if (_currentUserId() != sale.cashierUid) {
      throw const SaleConflictException('Your account has changed.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SaleConflictException('Your account is not authorized to sell for this store.');
    }
    if (response.statusCode == 409 || response.statusCode == 400) {
      // The server returns only curated business errors, but keep the device copy
      // and show a fixed translated message rather than arbitrary response text.
      throw const SaleConflictException(
        'The sale details changed. Review this sale before retrying.',
      );
    }
    if (response.statusCode != 200) {
      throw StateError(
        'Secure checkout is unavailable. Your receipt remains saved on this device.',
      );
    }
    final result = jsonDecode(response.body);
    if (result is! Map || result['id'] != sale.id || result['status'] != 'completed') {
      throw StateError('The server has not confirmed this receipt.');
    }
  }
}
