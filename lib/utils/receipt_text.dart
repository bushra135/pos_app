import '../app/app_language.dart';
import '../app/money.dart';
import '../models/sale_record.dart';

/// A plain-text receipt for WhatsApp, in the app's current language.
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

  static String message(SaleRecord sale) {
    final date = sale.createdAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final lines = <String>[
      sale.storeName,
      '${sale.receiptNumber} · ${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}',
      '',
      for (final line in sale.items)
        '${line.name}  ${line.quantity} × ${Money.format(line.price)} = ${Money.format(line.subtotal)}',
      '',
      if (sale.discount > 0) ...[
        '${'Subtotal'.tr}: ${Money.format(sale.subtotal)}',
        '${'Discount'.tr}: − ${Money.format(sale.discount)}',
      ],
      if (sale.vatRate > 0)
        '${'VAT {rate}% (included)'.trArgs({'rate': sale.vatRate.toStringAsFixed(0)})}: '
            '${Money.format(sale.tax)}',
      'Total: {amount}'.trArgs({'amount': Money.format(sale.total)}),
      'Payment: {method}'.trArgs({'method': sale.paymentMethod.tr}),
      '',
      'Thank you for shopping with us'.tr,
    ];
    return lines.join('\n');
  }

  /// wa.me link that opens WhatsApp with the receipt typed in; without a number the
  /// cashier picks the chat in WhatsApp.
  static Uri whatsappLink(SaleRecord sale, {String? number}) =>
      Uri.https('wa.me', number == null ? '/' : '/$number', {'text': message(sale)});
}
