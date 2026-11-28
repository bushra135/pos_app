import 'receipt_seal_service.dart';
import '../app/app_language.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/sale_record.dart';
import '../utils/receipt_layout.dart';

/// Generates the saved receipt from its fixed sale snapshot, never the live cart.
/// Same bilingual content as the screen ([ReceiptLayout]), on 80 mm receipt paper.
abstract final class ReceiptService {
  /// Lays out the receipt (or simplified tax invoice) as an 80 mm PDF.
  /// Arabic and English lines each get the right text direction.
  static Future<Uint8List> generatePdf(
    SaleRecord sale, {
    required String status,
    ReceiptSealData? verifiedSeal,
  }) async {
    final seal = verifiedSeal ?? await ReceiptSealService.load(sale);
    if (seal != null) sale = seal.sale;
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'));
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-SemiBold.ttf'),
    );
    final rtl = AppLanguage.isArabic;
    final layout = ReceiptLayout.of(sale);
    final document = pw.Document();
    pw.Widget text(String value, {double size = 9, bool bold = false, pw.TextAlign? align}) =>
        pw.Text(
          value,
          textAlign: align,
          textDirection: _direction(value),
          style: pw.TextStyle(
            font: bold ? boldFont : font,
            fontSize: size,
            wordSpacing: 1.15,
            fontWeight: bold ? pw.FontWeight.bold : null,
          ),
        );
    pw.Widget bilingual(String value, {double size = 9, bool bold = false, pw.TextAlign? align}) {
      final lines = value.split(' · ');
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++)
            text(
              lines[i],
              size: i == 0 ? size : size - 1,
              bold: bold && i == 0,
              align: align ?? (rtl ? pw.TextAlign.right : pw.TextAlign.left),
            ),
        ],
      );
    }

    pw.Widget row(ReceiptRow r, {double size = 9}) {
      final label = pw.Expanded(
        child: bilingual(r.label, size: size, bold: r.strong),
      );
      final value = pw.Expanded(
        child: bilingual(
          r.value,
          size: r.strong ? size + 1 : size,
          bold: r.strong,
          align: rtl ? pw.TextAlign.left : pw.TextAlign.right,
        ),
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rtl
              ? [value, pw.SizedBox(width: 10), label]
              : [label, pw.SizedBox(width: 10), value],
        ),
      );
    }

    pw.Widget productName(String value) {
      // Keep Arabic and Latin runs in separate paragraphs so PDF bidi/wrapping
      // never reverses an English brand or joins it to the Arabic name.
      final runs = <String>[];
      var buffer = StringBuffer();
      bool? arabic;
      for (final rune in value.runes) {
        final char = String.fromCharCode(rune);
        final script = RegExp(r'[؀-ۿ]').hasMatch(char)
            ? true
            : RegExp(r'[A-Za-z]').hasMatch(char)
            ? false
            : null;
        if (script != null && arabic != null && script != arabic) {
          if (buffer.toString().trim().isNotEmpty) runs.add(buffer.toString().trim());
          buffer = StringBuffer();
        }
        arabic = script ?? arabic;
        buffer.write(char);
      }
      if (buffer.toString().trim().isNotEmpty) runs.add(buffer.toString().trim());
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (final run in runs)
            text(run, bold: true, align: rtl ? pw.TextAlign.right : pw.TextAlign.left),
        ],
      );
    }

    pw.Widget item(SaleLine line) {
      final detail = pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            productName(line.name),
            text(
              '${line.quantity} x ${line.price.toStringAsFixed(3)}',
              size: 8,
              align: rtl ? pw.TextAlign.right : pw.TextAlign.left,
            ),
          ],
        ),
      );
      final amount = pw.SizedBox(
        width: 48,
        child: text(
          line.subtotal.toStringAsFixed(3),
          align: rtl ? pw.TextAlign.left : pw.TextAlign.right,
        ),
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rtl
              ? [amount, pw.SizedBox(width: 10), detail]
              : [detail, pw.SizedBox(width: 10), amount],
        ),
      );
    }

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
        theme: pw.ThemeData.withFont(
          base: font,
          bold: boldFont,
          italic: font,
          boldItalic: boldFont,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            text(sale.storeName, size: 14, bold: true, align: pw.TextAlign.center),
            for (final line in layout.storeLines)
              bilingual(line, size: 8, align: pw.TextAlign.center),
            pw.SizedBox(height: 6),
            bilingual(layout.title, size: 10, bold: true, align: pw.TextAlign.center),
            rule(),
            for (final r in layout.meta) row(r),
            if (layout.buyer.isNotEmpty) ...[rule(), for (final r in layout.buyer) row(r)],
            rule(),
            for (final line in sale.items) item(line),
            rule(),
            for (final r in layout.totals) row(r, size: 9.5),
            if (seal != null) ...[
              rule(),
              text('Digital receipt seal'.tr, size: 9, bold: true, align: pw.TextAlign.center),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: seal.url.toString(),
                  width: 105,
                  height: 105,
                ),
              ),
              pw.SizedBox(height: 4),
              text(
                'Scan to verify the amount and receipt number'.tr,
                size: 7,
                align: pw.TextAlign.center,
              ),
            ],
            pw.SizedBox(height: 8),
            bilingual(ReceiptLayout.thanks, size: 8, align: pw.TextAlign.center),
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
