import 'dart:convert';

import '../app/app_language.dart';

/// Texts for the browser camera overlay (web/browser_scanner.js), in the app's
/// current language. The overlay keeps its English text for any key left out.
String browserScannerStrings() => jsonEncode({
  'lang': AppLanguage.isArabic ? 'ar' : 'en',
  'dir': AppLanguage.isArabic ? 'rtl' : 'ltr',
  'scanAndSell': 'Scan and sell'.tr,
  'scanTitle': 'Scan & sell'.tr,
  'scanProduct': 'Scan product barcode'.tr,
  'close': 'Close'.tr,
  'starting': 'Starting camera...'.tr,
  'retry': 'Start / retry camera'.tr,
  'repeat': 'Add same item'.tr,
  'review': 'Review sale'.tr,
  'adding': 'Adding item...'.tr,
  'addFailed': 'Could not add item. Close the camera and check the sale.'.tr,
  'needsHttps': 'Open this HTTPS link in Safari to use the camera.'.tr,
  'readerFailed': 'Barcode reader failed to load. Reload the page.'.tr,
  'pointInline': 'Point at a barcode. Use + in the cart for identical items.'.tr,
  'pointContinuous': 'Scan items continuously. Use Add same item for identical products.'.tr,
  'pointSingle': 'Hold the barcode steady in front of the back camera.'.tr,
  'cameraDenied':
      'Camera access is blocked. Allow the camera for this site in the browser settings, then tap retry.'
          .tr,
  'cameraMissing': 'No camera was found. Use a barcode reader or type the barcode.'.tr,
  'cameraBusy': 'The camera is being used by another app or tab. Close it, then tap retry.'.tr,
  'cameraUnsupported':
      'This browser cannot open the camera here. Use a barcode reader or type the barcode.'.tr,
  'cameraFailed':
      'The camera could not start. Allow camera access, close other camera tabs, then tap retry.'
          .tr,
});
