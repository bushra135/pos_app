import 'dart:js_interop';

@JS('ShopPadBrowserScanner.open')
external JSPromise<JSAny?> _openScanner();

/// Opens a browser-owned camera and releases it on success or cancellation.
Future<String?> scanBrowserBarcode() async {
  final result = await _openScanner().toDart;
  return result == null ? null : (result as JSString).toDart;
}

@JS('ShopPadBrowserScanner.open')
external JSPromise<JSAny?> _openCheckout(
  JSFunction onBarcode,
  JSString summary,
);
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
  final action = await _openCheckout(callback, summary.toJS).toDart;
  return action != null && (action as JSString).toDart == 'review';
}

@JS('ShopPadBrowserScanner.position')
external void positionBrowserScanner(JSString bounds);
void positionBrowserCamera(String bounds) =>
    positionBrowserScanner(bounds.toJS);
