import 'package:flutter/services.dart';
import 'platform/scan_sound_native.dart'
    if (dart.library.js_interop) 'platform/scan_sound_web.dart'
    as platform;

/// One signal per accepted decode, independent of catalogue or stock availability.
Future<void> playBarcodeFeedback() async {
  try {
    await platform.playScanSound();
  } catch (_) {}
  try {
    await HapticFeedback.lightImpact();
  } catch (_) {}
}
