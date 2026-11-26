import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/app_language.dart';
import 'package:pos_app/services/platform/browser_scanner_strings.dart';

void main() {
  tearDown(() => AppLanguage.locale.value = AppLanguage.english);

  test('camera overlay texts follow the app language', () {
    final english = jsonDecode(browserScannerStrings()) as Map<String, dynamic>;
    expect(english['lang'], 'en');
    expect(english['dir'], 'ltr');
    expect(english['retry'], 'Start / retry camera');

    AppLanguage.locale.value = AppLanguage.arabic;
    final arabic = jsonDecode(browserScannerStrings()) as Map<String, dynamic>;
    expect(arabic['lang'], 'ar');
    expect(arabic['dir'], 'rtl');
    for (final key in english.keys.where((k) => k != 'lang' && k != 'dir')) {
      expect(arabic[key], isNot(english[key]), reason: '$key has no Arabic text');
      expect(
        RegExp(r'[A-Za-z]{4,}').hasMatch(arabic[key].replaceAll(RegExp('HTTPS|Safari'), '')),
        isFalse,
        reason: '$key still has English: ${arabic[key]}',
      );
    }
  });

  test('camera errors never show the browser error name', () {
    AppLanguage.locale.value = AppLanguage.arabic;
    final texts = (jsonDecode(browserScannerStrings()) as Map<String, dynamic>).values.join(' ');
    for (final raw in [
      'NotSupportedError',
      'NotAllowedError',
      'NotFoundError',
      'NotReadableError',
    ]) {
      expect(texts.contains(raw), isFalse);
    }
  });
}
