import '../app/money.dart';
import '../models/sale_record.dart';
import 'receipt_layout.dart';

/// A plain-text bilingual receipt for WhatsApp.
abstract final class ReceiptText {
  /// Digits for a wa.me link, or null when the number is not usable.
  /// Local Bahraini numbers (8 digits) get the 973 country code.
  static String? whatsappNumber(String input) {
    var digits = input.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.startsWith('+')) digits = digits.substring(1);
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (!RegExp(r'^[0-9]+$').hasMatch(digits)) return null;
    if (digits.length == 8) digits = '973$digits';
    if (digits.length < 10 || digits.length > 15) return null;
    return digits;
  }

  /// The bilingual receipt as plain text: same content as the screen and the PDF.
  static String message(SaleRecord sale) {
    final layout = ReceiptLayout.of(sale);
    String row(ReceiptRow r) => '${r.label}: ${r.value}';
    return [
      sale.storeName,
      ...layout.storeLines,
      layout.title,
      '',
      for (final r in layout.meta) row(r),
      if (layout.buyer.isNotEmpty) ...['', for (final r in layout.buyer) row(r)],
      '',
      for (final line in sale.items)
        '${line.name}  ${line.quantity} × ${Money.format(line.price)} = ${Money.format(line.subtotal)}',
      '',
      for (final r in layout.totals) row(r),
      '',
      ReceiptLayout.thanks,
    ].join('\n');
  }

  /// wa.me link that opens WhatsApp with the receipt typed in; without a number the
  /// cashier picks the chat in WhatsApp.
  static Uri whatsappLink(SaleRecord sale, {String? number}) =>
      Uri.https('wa.me', number == null ? '/' : '/$number', {'text': message(sale)});
}
