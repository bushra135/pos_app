/// Conservative, offline suggestions. Unknown or ambiguous names stay blank.
class ProductCategorySuggestion {
  static String? fromName(String name) {
    final text = name
        .toLowerCase()
        .replaceAll(RegExp('[أإآ]'), 'ا')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
        .trim();
    if (text.isEmpty) return null;
    // Match phrases first so chocolate milk is not classified as confectionery.
    for (final phrase in [
      'chocolate milk',
      'حليب بالشوكولاتة',
      'حليب شوكولاتة',
    ]) {
      if (text.contains(phrase)) return 'Dairy';
    }
    final matches = <String>{};
    for (final entry in _terms.entries) {
      for (final term in entry.value) {
        if ((' $text ').contains(' $term ')) {
          matches.add(entry.key);
          break;
        }
      }
    }
    return matches.length == 1 ? matches.single : null;
  }

  static const _terms = <String, List<String>>{
    'Stationery': [
      'pen',
      'pens',
      'pencil',
      'pencils',
      'notebook',
      'notebooks',
      'eraser',
      'ruler',
      'stapler',
      'crayons',
      'قلم',
      'اقلام',
      'دفتر',
      'دفاتر',
      'ممحاة',
      'مسطرة',
      'دباسة',
    ],
    'Dairy': [
      'milk',
      'cheese',
      'yogurt',
      'yoghurt',
      'butter',
      'حليب',
      'جبن',
      'جبنة',
      'زبادي',
      'زبدة',
    ],
    'Beverages': [
      'water',
      'juice',
      'coffee',
      'tea',
      'soda',
      'pepsi',
      'cola',
      'ماء',
      'مياه',
      'عصير',
      'قهوة',
      'شاي',
      'بيبسي',
      'كولا',
    ],
    'Snacks': ['chips', 'crisps', 'popcorn', 'nuts', 'شيبس', 'فشار', 'مكسرات'],
    'Sweets': [
      'chocolate',
      'candy',
      'biscuits',
      'cookies',
      'nutella',
      'شوكولاتة',
      'شوكولاته',
      'حلوى',
      'بسكويت',
      'نوتيلا',
    ],
    'Bakery': ['bread', 'croissant', 'bagel', 'خبز', 'كرواسون'],
    'Groceries': [
      'rice',
      'pasta',
      'flour',
      'sugar',
      'salt',
      'ارز',
      'رز',
      'معكرونة',
      'طحين',
      'سكر',
      'ملح',
    ],
    'Personal Care': [
      'shampoo',
      'toothpaste',
      'deodorant',
      'conditioner',
      'شامبو',
      'معجون اسنان',
      'مزيل عرق',
    ],
    'Cleaning Supplies': [
      'detergent',
      'bleach',
      'dishwashing',
      'منظف',
      'مبيض',
      'سائل جلي',
      'مسحوق غسيل',
    ],
    'Electronics': [
      'charger',
      'headphones',
      'earbuds',
      'keyboard',
      'شاحن',
      'سماعات',
      'لوحة مفاتيح',
    ],
    'Clothing': ['shirt', 'socks', 'jeans', 'قميص', 'جوارب', 'بنطلون'],
    'Books': ['book', 'novel', 'كتاب', 'رواية'],
  };
}
