/// Pure helpers for turning pasted recipe text into clean ingredient names.
/// Kept free of Flutter imports so it can be unit-tested directly.
library;

const _unitWords = {
  'cup', 'cups', 'tbsp', 'tsp', 'tablespoon', 'tablespoons',
  'teaspoon', 'teaspoons', 'g', 'kg', 'gram', 'grams', 'ml', 'l',
  'litre', 'litres', 'liter', 'liters', 'pinch', 'oz', 'lb', 'lbs',
  'piece', 'pieces', 'pcs', 'clove', 'cloves', 'can', 'cans',
  'packet', 'packets', 'pack', 'slice', 'slices', 'bunch',
};

/// Parses pasted recipe text into clean, de-duplicated ingredient names.
/// Strips leading bullets/numbers/quantities, common units, and prep notes
/// after a comma or parenthesis.
List<String> parseIngredients(String text) {
  final lines = text.split('\n');
  final result = <String>[];
  final seen = <String>{};
  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) continue;
    // Remove leading bullets / list markers / numbering.
    line = line.replaceFirst(RegExp(r'^[\-\*•\u2022\d\.\)\s]+'), '');
    // Drop anything after a comma or parenthesis (prep notes).
    line = line.split(RegExp(r'[,(]')).first.trim();
    if (line.isEmpty) continue;
    // Tokenize and strip leading quantity + unit tokens.
    final tokens = line.split(RegExp(r'\s+'));
    var start = 0;
    while (start < tokens.length) {
      final t =
          tokens[start].toLowerCase().replaceAll(RegExp(r'[^a-z0-9/.]'), '');
      final isNumber = RegExp(r'^[\d/.]+$').hasMatch(t);
      if (isNumber || _unitWords.contains(t)) {
        start++;
      } else {
        break;
      }
    }
    final name = tokens.sublist(start).join(' ').trim();
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    if (seen.add(key)) result.add(name);
  }
  return result;
}

/// For a list of ingredient names, reports which are already in stock and which
/// are missing, given the list of in-stock inventory names. Case-insensitive;
/// matches if a stock name contains the ingredient or vice versa.
({List<String> inStock, List<String> missing}) matchIngredientNames(
    List<String> ingredients, List<String> stockNames) {
  final lowered = stockNames.map((s) => s.toLowerCase()).toList();
  final inStock = <String>[];
  final missing = <String>[];
  for (final raw in ingredients) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    final lower = name.toLowerCase();
    final found = lowered
        .any((s) => s == lower || s.contains(lower) || lower.contains(s));
    (found ? inStock : missing).add(name);
  }
  return (inStock: inStock, missing: missing);
}
