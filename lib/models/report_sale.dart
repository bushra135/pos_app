import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Read-only analytics view of current and legacy sale documents.
/// This does not replace SaleRecord, the immutable checkout/queue snapshot.
class ReportSale {
  final double grossSales;
  final double netSales;
  final double discount;
  final double refund;
  final bool isRefund;
  final String paymentMethod;
  final List<Map<String, dynamic>> items;

  const ReportSale({
    required this.grossSales,
    required this.netSales,
    required this.discount,
    required this.refund,
    required this.isRefund,
    required this.paymentMethod,
    required this.items,
  });

  factory ReportSale.fromMap(Map<String, dynamic> data) {
    // Read field names in priority order to support current and older Firestore records.
    final explicitTotal = reportNumber(data, [
      'netTotal',
      'grandTotal',
      'total',
      'totalAmount',
      'amount',
    ]);

    final discount = reportNumber(data, [
      'discount',
      'discountAmount',
      'totalDiscount',
    ]).abs();

    final status = (data['status'] ?? data['type'] ?? '')
        .toString()
        .toLowerCase();

    final isRefund =
        status.contains('refund') ||
        status.contains('return') ||
        status.contains('cancel');

    final refundAmount = reportNumber(data, [
      'refund',
      'refundAmount',
      'totalRefund',
      'returnedAmount',
    ]).abs();

    final refund = refundAmount > 0
        ? refundAmount
        : isRefund
        ? explicitTotal.abs()
        : 0.0;

    final explicitGross = reportNumber(data, [
      'grossTotal',
      'subtotal',
      'subTotal',
      'totalBeforeDiscount',
      'beforeDiscount',
    ]);

    final grossSales = isRefund
        ? 0.0
        : explicitGross > 0
        ? explicitGross
        : explicitTotal + discount;

    // Refund documents reduce net sales; refunds within a sale reduce that sale's total.
    final double netSales = isRefund
        ? -refund
        : math.max(0.0, explicitTotal - refund);

    final rawItems = data['items'] ?? data['cartItems'] ?? data['products'];
    final items = <Map<String, dynamic>>[];

    if (rawItems is List) {
      for (final item in rawItems) {
        final itemMap = reportMap(item);
        if (itemMap.isNotEmpty) items.add(itemMap);
      }
    }

    return ReportSale(
      grossSales: grossSales,
      netSales: netSales,
      discount: discount,
      refund: refund,
      isRefund: isRefund,
      paymentMethod: reportPaymentLabel(
        data['paymentMethod'] ?? data['paymentType'] ?? data['payment'],
      ),
      items: items,
    );
  }
}

/// Accept Firestore timestamps and the date formats used by older records.
DateTime? reportDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Normalize map keys before reading an imported or legacy item.
Map<String, dynamic> reportMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;

  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  return {};
}

/// Link inventory and sale lines by barcode, then ID, then normalized name.
String reportProductKey(Map<String, dynamic> data, String fallbackName) {
  final barcode = (data['barcode'] ?? '').toString().trim();
  final productId = (data['productId'] ?? data['id'] ?? '').toString().trim();

  if (barcode.isNotEmpty) return barcode;
  if (productId.isNotEmpty) return productId;

  return fallbackName.trim().toLowerCase();
}

/// Read the first supported numeric field, preserving an explicit zero.
double reportNumber(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];

    if (value is num) return value.toDouble();

    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
  }

  return 0;
}

/// Keep payment grouping consistent between reports and local insights.
String reportPaymentLabel(dynamic value) {
  final raw = (value ?? 'Unknown').toString().trim().toLowerCase();

  if (raw.isEmpty) return 'Unknown';
  if (raw.contains('cash')) return 'Cash';
  if (raw.contains('benefit')) return 'BenefitPay';
  if (raw.contains('card') || raw.contains('visa') || raw.contains('mada')) {
    return 'Card';
  }
  if (raw.contains('apple')) return 'Apple Pay';
  if (raw.contains('transfer') || raw.contains('bank')) {
    return 'Bank Transfer';
  }

  return raw[0].toUpperCase() + raw.substring(1);
}
