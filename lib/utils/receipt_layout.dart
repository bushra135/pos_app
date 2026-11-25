import '../app/money.dart';
import '../models/sale_record.dart';
import 'vat_invoice.dart';

/// One labelled value on a receipt.
typedef ReceiptRow = ({String label, String value, bool strong});

/// The receipt's content, bilingual (Arabic · English), shared by the screen, the PDF
/// and the WhatsApp text so all three always say the same thing.
///
/// Formats (NBR VAT invoicing rules):
/// - VAT-registered store → "Simplified Tax Invoice": store name, address and VAT
///   number, date, items, total including VAT, VAT rate and amount.
/// - Registered store + customer details → "Tax Invoice": adds the customer's name,
///   address and VAT number, quantities and the sequential number.
/// - Store not registered → "Receipt": no VAT is shown, because none is collected.
class ReceiptLayout {
  ReceiptLayout._(this.sale);

  final SaleRecord sale;

  factory ReceiptLayout.of(SaleRecord sale) => ReceiptLayout._(sale);

  bool get isTaxInvoice =>
      sale.invoiceKind == InvoiceKind.simplified || sale.invoiceKind == InvoiceKind.full;

  String get title => switch (sale.invoiceKind) {
    InvoiceKind.full => 'فاتورة ضريبية · Tax Invoice',
    InvoiceKind.simplified => 'فاتورة ضريبية مبسطة · Simplified Tax Invoice',
    _ => 'إيصال · Receipt',
  };

  /// Lines under the store name: address and, on tax invoices, the VAT number.
  List<String> get storeLines => [
    if (sale.storeAddress.isNotEmpty) sale.storeAddress,
    if (isTaxInvoice && sale.storeVatNumber.isNotEmpty)
      'رقم حساب ض.ق.م · VAT No. ${VatChecks.pretty(sale.storeVatNumber)}',
  ];

  String get date {
    final d = sale.createdAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  List<ReceiptRow> get meta => [
    (
      label: 'رقم الفاتورة · No.',
      value: sale.invoiceNumber.isNotEmpty ? sale.invoiceNumber : sale.receiptNumber,
      strong: true,
    ),
    (label: 'التاريخ · Date', value: date, strong: false),
    if (sale.cashierName.isNotEmpty)
      (label: 'الكاشير · Cashier', value: sale.cashierName, strong: false),
  ];

  /// Customer block of a full tax invoice.
  List<ReceiptRow> get buyer => [
    if (sale.buyerName.isNotEmpty)
      (label: 'العميل · Customer', value: sale.buyerName, strong: true),
    if (sale.buyerAddress.isNotEmpty)
      (label: 'العنوان · Address', value: sale.buyerAddress, strong: false),
    if (sale.buyerVatNumber.isNotEmpty)
      (
        label: 'رقم ض.ق.م للعميل · Customer VAT No.',
        value: VatChecks.pretty(sale.buyerVatNumber),
        strong: false,
      ),
  ];

  List<ReceiptRow> get totals {
    final otherDiscount = sale.discount - sale.offerDiscount;
    return [
      if (sale.discount > 0) ...[
        (label: 'المجموع · Subtotal', value: Money.format(sale.subtotal), strong: false),
        if (sale.offerDiscount > 0)
          (
            label: 'عرض مجمّع · Bundle offer',
            value: '− ${Money.format(sale.offerDiscount)}',
            strong: false,
          ),
        if (otherDiscount > 0.0005)
          (label: 'خصم · Discount', value: '− ${Money.format(otherDiscount)}', strong: false),
      ],
      if (sale.vatRate > 0) ...[
        (
          label: 'المبلغ قبل الضريبة · Excl. VAT',
          value: Money.format(sale.total - sale.tax),
          strong: false,
        ),
        (
          // The rate sits in the English half only: a % inside the Arabic half jumps
          // to the wrong end when the line is shown left to right.
          label: 'ضريبة القيمة المضافة · VAT ${sale.vatRate.toStringAsFixed(0)}%',
          value: Money.format(sale.tax),
          strong: false,
        ),
        (
          label: 'الإجمالي شامل الضريبة · Total incl. VAT',
          value: Money.format(sale.total),
          strong: true,
        ),
      ] else
        (label: 'الإجمالي · Total', value: Money.format(sale.total), strong: true),
      (label: 'الدفع · Paid by', value: _payment(sale.paymentMethod), strong: false),
    ];
  }

  static String _payment(String method) => switch (method) {
    'Cash' => 'نقداً · Cash',
    _ => method,
  };

  static const thanks = 'شكراً لتسوقكم · Thank you';
}
