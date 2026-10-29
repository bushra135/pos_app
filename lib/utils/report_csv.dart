/// UTF-8 CSV content for Excel, with safe literal text and BD precision.
abstract final class ReportCsv {
  static String encode(List<List<Object?>> rows) =>
      '\ufeff${rows.map((row) => row.map(_cell).join(',')).join('\r\n')}\r\n';
  static String _cell(Object? value) {
    if (value == null) return '';
    if (value is int) return value.toString();
    if (value is num) return value.isFinite ? value.toStringAsFixed(3) : '';
    var text = value.toString();
    // Quotes alone do not prevent spreadsheet applications executing formulas.
    if (RegExp(r'^\s*[=+@-]').hasMatch(text) ||
        text.startsWith('\t') ||
        text.startsWith('\r') ||
        text.startsWith('\n')) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}
