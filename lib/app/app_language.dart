import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'arabic_strings.dart';

/// App language (English or Arabic) chosen on this device.
///
/// Screens call `'English text'.tr`; in Arabic the text comes from [arabicStrings]
/// and the whole layout runs right-to-left. Unknown texts fall back to English,
/// so a missing translation never hides a label.
abstract final class AppLanguage {
  static const english = Locale('en');
  static const arabic = Locale('ar');
  static const supported = [english, arabic];
  static const _key = 'app_language';

  static final ValueNotifier<Locale> locale = ValueNotifier(english);

  static bool get isArabic => locale.value.languageCode == 'ar';

  /// Restores the saved choice; English when nothing was saved or storage is blocked.
  static Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      if (saved == 'ar') locale.value = arabic;
    } catch (_) {
      // Private browsing or blocked storage: keep English.
    }
  }

  static Future<void> set(Locale value) async {
    locale.value = value;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, value.languageCode);
    } catch (_) {
      // The choice still applies for this session.
    }
  }

  static Future<void> toggle() => set(isArabic ? english : arabic);
}

/// Adds .tr and .trArgs to English UI strings.
extension Translate on String {
  /// This text in the current app language.
  String get tr => AppLanguage.isArabic ? (arabicStrings[this] ?? this) : this;

  /// Translates a template such as `'Hi, {name}'`, then fills in the values.
  String trArgs(Map<String, Object?> values) {
    var text = tr;
    values.forEach((key, value) => text = text.replaceAll('{$key}', '${value ?? ''}'));
    return text;
  }
}
