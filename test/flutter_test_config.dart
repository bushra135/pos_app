import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads the app's real fonts before every test file, so layout tests measure text
/// the way the app draws it instead of with the wide square test font.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Device storage (language choice, invoice counter); tests may set their own values.
  SharedPreferences.setMockInitialValues({});
  final plex = FontLoader('IBMPlexSansArabic');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    plex.addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-$weight.ttf'));
  }
  await plex.load();
  await (FontLoader('Cairo')..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
  await testMain();
}
