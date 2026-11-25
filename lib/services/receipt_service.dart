import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/sale_record.dart';
import '../utils/receipt_layout.dart';

/// Generates the saved receipt from its fixed sale snapshot, never the live cart.
/// Same bilingual content as the screen ([ReceiptLayout]), on 80 mm receipt paper.
abstract final class ReceiptService {
  static Future<Uint8List> generatePdf(SaleRecord sale, {required String status}) async {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo.ttf'));
    final layout = ReceiptLayout.of(sale);
    final document = pw.Document();
    pw.Widget text(String value, {double size = 9, bool bold = false, pw.TextAlign? align}) =>
        pw.Text(
          value,
          textAlign: align,
          textDirection: _direction(value),
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null),
        );
    pw.Widget row(ReceiptRow r, {double size = 9}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: text(r.label, size: size, bold: r.strong),
          ),
          pw.SizedBox(width: 6),
          text(r.value, size: r.strong ? size + 2 : size, bold: r.strong),
        ],
      ),
    );
    pw.Widget rule() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Divider(
        thickness: 0.5,
        color: PdfColors.grey500,
        borderStyle: pw.BorderStyle.dashed,
      ),
    );
    // One continuous page, like a till roll: roll paper has no fixed height.
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80.copyWith(marginLeft: 12, marginRight: 12),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            text(sale.storeName, size: 14, bold: true, align: pw.TextAlign.center),
            for (final line in layout.storeLines) text(line, size: 8, align: pw.TextAlign.center),
            pw.SizedBox(height: 6),
            text(layout.title, size: 10, bold: true, align: pw.TextAlign.center),
            rule(),
            for (final r in layout.meta) row(r),
            if (layout.buyer.isNotEmpty) ...[rule(), for (final r in layout.buyer) row(r)],
            rule(),
            for (final line in sale.items)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          text(line.name, bold: true),
                          text('${line.quantity} x ${line.price.toStringAsFixed(3)}', size: 8),
                        ],
                      ),
                    ),
                    text(line.subtotal.toStringAsFixed(3)),
                  ],
                ),
              ),
            rule(),
            for (final r in layout.totals) row(r, size: 9.5),
            pw.SizedBox(height: 8),
            text(ReceiptLayout.thanks, size: 8, align: pw.TextAlign.center),
            if (status.isNotEmpty) text(status, size: 7, align: pw.TextAlign.center),
          ],
        ),
      ),
    );
    return document.save();
  }

  static pw.TextDirection _direction(String text) =>
      RegExp(r'[؀-ۿ]').hasMatch(text) ? pw.TextDirection.rtl : pw.TextDirection.ltr;
}
