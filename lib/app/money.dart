import 'app_language.dart';

/// Bahraini dinar amounts, written the way each language reads them:
/// `BD 2.250` in English and `2.250 د.ب` in Arabic. Always three decimals (fils).
abstract final class Money {
  /// Currency mark for input suffixes and column headers.
  static String get symbol => AppLanguage.isArabic ? 'د.ب' : 'BD';

  static String format(num amount) {
    final value = amount.toStringAsFixed(3);
    return AppLanguage.isArabic ? '$value د.ب' : 'BD $value';
  }
}
