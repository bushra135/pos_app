import 'dart:js_interop';

const supportsReportDownload = true;
@JS('ShopPadReportExport.download')
external void _download(JSString workbookBase64, JSString filename);
Future<void> downloadReport(String workbookBase64, String filename) async =>
    _download(workbookBase64.toJS, filename.toJS);
