import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// The store's VAT status as the owner set it (stores/{code}: vatRegistered, vatNumber,
/// storeAddress), following the NBR's tax invoice rules.
class StoreVat {
  const StoreVat({
    required this.configured,
    required this.registered,
    required this.number,
    required this.address,
  });

  /// False for stores that have not filled in their VAT details yet.
  final bool configured;
  final bool registered;

  /// 15-digit VAT account number; empty when not registered.
  final String number;
  final String address;

  static const bahrainRate = 10.0;

  factory StoreVat.fromStore(Map<String, dynamic>? store) {
    final data = store ?? const {};
    return StoreVat(
      configured: data.containsKey('vatRegistered'),
      registered: data['vatRegistered'] == true,
      number: (data['vatNumber'] ?? '').toString(),
      address: (data['storeAddress'] ?? '').toString(),
    );
  }

  /// VAT included in prices. A store that is not registered collects no VAT, so none
  /// is shown or recorded. Stores that have not set their details yet keep the earlier
  /// behaviour (10% shown as included) until the owner fills them in.
  double get rate => !configured || registered ? bahrainRate : 0;

  /// What the receipt is: a VAT invoice needs the store's VAT number.
  bool get issuesTaxInvoices => configured && registered && number.length == 15;
}

/// The three receipt formats.
abstract final class InvoiceKind {
  /// Not VAT-registered (or details not set yet): a plain receipt, no VAT.
  static const receipt = 'receipt';

  /// Registered store, customer not VAT-registered or the supply is BHD 500 or less.
  static const simplified = 'simplified';

  /// Registered store and a customer who asks for one (name, address, VAT number).
  static const full = 'full';

  static String forSale({required StoreVat vat, required bool buyerDetails}) {
    if (!vat.issuesTaxInvoices) return receipt;
    return buyerDetails ? full : simplified;
  }

  /// Above this a VAT-registered customer needs a full tax invoice (NBR).
  static const simplifiedLimit = 500.0;
}

abstract final class VatChecks {
  static String digits(String value) => value.replaceAll(RegExp(r'[\s-]'), '');

  /// English error for `.tr`, or null. Empty is allowed only when not registered.
  static String? vatNumber(String value, {required bool required}) {
    final number = digits(value);
    if (number.isEmpty) return required ? 'Enter the 15-digit VAT account number' : null;
    if (!RegExp(r'^[0-9]{15}$').hasMatch(number)) {
      return 'The VAT account number has 15 digits';
    }
    return null;
  }

  /// The address on a tax invoice: branch, city and country; a PO box alone is not enough.
  static String? address(String value, {required bool required}) {
    final text = value.trim();
    if (text.isEmpty) return required ? 'Enter the store address' : null;
    if (text.length > 200) return 'Use 200 characters or fewer';
    final onlyPoBox = RegExp(
      r'^(p\.?\s*o\.?\s*box|ص\.?\s*ب|صندوق بريد)[\s\d.:#-]*$',
      caseSensitive: false,
    );
    if (onlyPoBox.hasMatch(text)) return 'A PO box alone is not enough: add the shop location';
    return null;
  }

  /// "123456789012345" → "1234 5678 9012 345" for reading on a receipt.
  static String pretty(String number) {
    final d = digits(number);
    if (d.length != 15) return d;
    return '${d.substring(0, 4)} ${d.substring(4, 8)} ${d.substring(8, 12)} ${d.substring(12)}';
  }
}

/// Sequential invoice numbers that stay unique when several phones sell offline:
/// INV-[device code]-[counter], e.g. INV-KQM-000245. The code is made once per device;
/// the counter counts up per store on that device.
class InvoiceNumbers {
  InvoiceNumbers(this._prefs, {Random? random}) : _random = random ?? Random.secure();

  final SharedPreferences _prefs;
  final Random _random;
  static const _letters = 'ACDEFGHJKMNPQRTUVWXY'; // no look-alikes (B/8, I/1, O/0, S/5, Z/2)

  String get deviceCode {
    var code = _prefs.getString('invoiceDevice') ?? '';
    if (code.length != 3) {
      code = List.generate(3, (_) => _letters[_random.nextInt(_letters.length)]).join();
      _prefs.setString('invoiceDevice', code);
    }
    return code;
  }

  Future<String> next(String storeCode) async {
    final key = 'invoiceCounter_$storeCode';
    final value = (_prefs.getInt(key) ?? 0) + 1;
    await _prefs.setInt(key, value);
    return 'INV-$deviceCode-${value.toString().padLeft(6, '0')}';
  }
}
