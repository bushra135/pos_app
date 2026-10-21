import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/sale_record.dart';

/// Generates the saved receipt from its fixed sale snapshot, never the live cart.
abstract final class ReceiptService {
  static Future<Uint8List> generatePdf(
    SaleRecord sale, {
    required String status,
  }) async {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo.ttf'));
    final document = pw.Document();
    final date = sale.createdAt.toLocal().toString().split('.').first;
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Text(
            sale.storeName,
            style: const pw.TextStyle(fontSize: 22),
            textDirection: _direction(sale.storeName),
          ),
          pw.Text('Sales receipt', style: const pw.TextStyle(fontSize: 16)),
          pw.SizedBox(height: 12),
          pw.Text(sale.receiptNumber),
          pw.Text(date),
          pw.Text(
            'Cashier: ${sale.cashierName}',
            textDirection: _direction(sale.cashierName),
          ),
          pw.Text('Payment: ${sale.paymentMethod}'),
          pw.Text('Status: $status'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Qty', 'Unit price (BD)', 'Amount (BD)'],
            data: sale.items
                .map(
                  (line) => [
                    line.name,
                    '${line.quantity}',
                    line.price.toStringAsFixed(3),
                    line.subtotal.toStringAsFixed(3),
                  ],
                )
                .toList(),
            cellBuilder: (column, value, row) => pw.Text(
              value.toString(),
              textDirection: _direction(value.toString()),
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total: BD ${sale.total.toStringAsFixed(3)}',
              style: const pw.TextStyle(fontSize: 18),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Thank you for shopping with us.'),
        ],
        footer: (context) => pw.Text(
          'ShopPad | ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
    );
    return document.save();
  }

  static pw.TextDirection _direction(String text) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(text)
      ? pw.TextDirection.rtl
      : pw.TextDirection.ltr;
}
