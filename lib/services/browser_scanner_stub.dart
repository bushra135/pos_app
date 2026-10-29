Future<String?> scanBrowserBarcode() async => null;

void closeBrowserScanner() {}
Future<bool> scanBrowserCheckout({
  required Future<String> Function(String) onBarcode,
  required String summary,
}) async => false;

void positionBrowserCamera(String bounds) {}
