import 'dart:js_interop';

const supportsReportDownload = true;
@JS('ShopPadReportExport.download')
external void _download(JSString csv, JSString filename);
Future<void> downloadReport(String csv, String filename) async =>
    _download(csv.toJS, filename.toJS);
