import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/app_language.dart';
import 'package:pos_app/app/arabic_strings.dart';

void main() {
  tearDown(() => AppLanguage.locale.value = AppLanguage.english);

  test('English is the default and texts stay as written', () {
    expect(AppLanguage.isArabic, isFalse);
    expect('Start sale'.tr, 'Start sale');
    expect('Hi, {name}'.trArgs({'name': 'Noora'}), 'Hi, Noora');
  });

  test('Arabic translates known texts, fills templates and keeps unknown text', () {
    AppLanguage.locale.value = AppLanguage.arabic;
    expect('Start sale'.tr, 'ابدأ البيع');
    expect('Hi, {name}'.trArgs({'name': 'نورة'}), 'مرحباً، نورة');
    expect('Held sales ({n})'.trArgs({'n': 2}), 'المبيعات المعلّقة (2)');
    expect('A product name nobody translated'.tr, 'A product name nobody translated');
  });

  test('every template keeps the same placeholders in Arabic', () {
    final placeholder = RegExp(r'\{(\w+)\}');
    for (final entry in arabicStrings.entries) {
      final english = placeholder.allMatches(entry.key).map((m) => m.group(1)).toSet();
      final arabic = placeholder.allMatches(entry.value).map((m) => m.group(1)).toSet();
      expect(arabic, english, reason: entry.key);
    }
  });
}
