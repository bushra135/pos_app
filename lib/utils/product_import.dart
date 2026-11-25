/// One product row pasted from a spreadsheet.
class ImportedProduct {
  const ImportedProduct({
    required this.line,
    required this.barcode,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    this.cost,
  });

  final int line;
  final String barcode;
  final String name;
  final String category;
  final double price;
  final int stock;
  final double? cost;
}

/// What a paste contains: rows ready to import, rows skipped because the barcode already
/// exists, and rows with a problem (line number + English reason for `.tr`).
class ProductImport {
  const ProductImport(this.ready, this.duplicates, this.errors);

  final List<ImportedProduct> ready;
  final List<String> duplicates;
  final List<({int line, String reason})> errors;

  static const columns = 'Barcode, Name, Category, Price, Stock, Cost (optional)';

  /// Parses rows copied from Excel or Google Sheets (tab-separated) or CSV.
  /// A first row that looks like a header is skipped.
  static ProductImport parse(String text, {Set<String> existingBarcodes = const {}}) {
    final ready = <ImportedProduct>[];
    final duplicates = <String>[];
    final errors = <({int line, String reason})>[];
    final seen = <String>{...existingBarcodes};
    final lines = text.replaceAll('\r', '').split('\n');
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      if (raw.trim().isEmpty) continue;
      final separator = raw.contains('\t') ? '\t' : (raw.contains(';') ? ';' : ',');
      final cells = raw.split(separator).map((cell) => cell.trim()).toList();
      final line = i + 1;
      if (ready.isEmpty && errors.isEmpty && duplicates.isEmpty && _looksLikeHeader(cells)) {
        continue;
      }
      if (cells.length < 5) {
        errors.add((
          line: line,
          reason: 'Needs at least 5 columns: barcode, name, category, price, stock',
        ));
        continue;
      }
      final barcode = cells[0];
      final name = cells[1];
      final category = cells[2];
      final price = double.tryParse(cells[3].replaceAll(',', '.'));
      final stock = int.tryParse(cells[4]);
      final costText = cells.length > 5 ? cells[5].replaceAll(',', '.') : '';
      final cost = costText.isEmpty ? null : double.tryParse(costText);
      final reason = barcode.isEmpty || barcode.contains('/')
          ? 'Missing or invalid barcode'
          : name.isEmpty || name.length > 80
          ? 'Missing name, or longer than 80 characters'
          : price == null || !price.isFinite || price < 0
          ? 'Price must be a number of 0 or more'
          : stock == null || stock < 0
          ? 'Stock must be a whole number of 0 or more'
          : costText.isNotEmpty && (cost == null || !cost.isFinite || cost < 0)
          ? 'Cost must be a number of 0 or more'
          : null;
      if (reason != null) {
        errors.add((line: line, reason: reason));
        continue;
      }
      if (!seen.add(barcode)) {
        duplicates.add(barcode);
        continue;
      }
      ready.add(
        ImportedProduct(
          line: line,
          barcode: barcode,
          name: name,
          category: category.isEmpty ? 'General' : category,
          price: price!,
          stock: stock!,
          cost: cost,
        ),
      );
    }
    return ProductImport(ready, duplicates, errors);
  }

  static bool _looksLikeHeader(List<String> cells) =>
      cells.length >= 4 && double.tryParse(cells[3].replaceAll(',', '.')) == null;
}
