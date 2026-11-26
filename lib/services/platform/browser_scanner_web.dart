import 'dart:js_interop';

import 'browser_scanner_strings.dart';

@JS('ShopPadBrowserScanner.setStrings')
external void _setStrings(JSString json);

/// The overlay shows its texts in the app's current language.
void _sendStrings() {
  try {
    _setStrings(browserScannerStrings().toJS);
  } catch (_) {
    // An older cached overlay without setStrings keeps its English texts.
  }
}

@JS('ShopPadBrowserScanner.open')
external JSPromise<JSAny?> _openScanner();

/// Opens a browser-owned camera and releases it on success or cancellation.
Future<String?> scanBrowserBarcode() async {
  _sendStrings();
  final result = await _openScanner().toDart;
  return result == null ? null : (result as JSString).toDart;
}

@JS('ShopPadBrowserScanner.open')
external JSPromise<JSAny?> _openCheckout(JSFunction onBarcode, JSString summary);
@JS('ShopPadBrowserScanner.close')
external void closeBrowserScanner();

/// Keeps the browser camera open while each barcode is added to the live cart.
Future<bool> scanBrowserCheckout({
  required Future<String> Function(String) onBarcode,
  required String summary,
}) async {
  final callback = ((JSString code) => onBarcode(
    code.toDart,
  ).then((result) => result.toJS).toJS).toJS;
  _sendStrings();
  final action = await _openCheckout(callback, summary.toJS).toDart;
  return action != null && (action as JSString).toDart == 'review';
}

@JS('ShopPadBrowserScanner.position')
external void positionBrowserScanner(JSString bounds);
void positionBrowserCamera(String bounds) => positionBrowserScanner(bounds.toJS);
