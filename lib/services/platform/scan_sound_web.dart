import 'dart:js_interop';

@JS('ShopPadBrowserScanner.playScanSound')
external void _playScanSound();
Future<void> playScanSound() async => _playScanSound();
