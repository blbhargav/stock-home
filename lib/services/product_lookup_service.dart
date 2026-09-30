import 'dart:convert';

import 'package:http/http.dart' as http;

/// A product looked up from a barcode.
class ProductInfo {
  const ProductInfo({required this.name, this.category});

  final String name;
  final String? category;
}

/// Looks up product details from a barcode using the Open Food Facts API.
///
/// Open Food Facts is a free, open database. No API key required.
class ProductLookupService {
  ProductLookupService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Maps Open Food Facts categories to the app's category list.
  static const _categoryHints = <String, String>{
    'beverage': 'Beverages',
    'drink': 'Beverages',
    'water': 'Beverages',
    'juice': 'Beverages',
    'dairy': 'Dairy & Eggs',
    'milk': 'Dairy & Eggs',
    'cheese': 'Dairy & Eggs',
    'yogurt': 'Dairy & Eggs',
    'egg': 'Dairy & Eggs',
    'meat': 'Meat & Seafood',
    'poultry': 'Meat & Seafood',
    'fish': 'Meat & Seafood',
    'seafood': 'Meat & Seafood',
    'fruit': 'Fruits & Vegetables',
    'vegetable': 'Fruits & Vegetables',
    'bread': 'Bakery',
    'baker': 'Bakery',
    'frozen': 'Frozen',
    'snack': 'Snacks',
    'biscuit': 'Snacks',
    'chocolate': 'Snacks',
    'cereal': 'Pantry & Dry Goods',
    'pasta': 'Pantry & Dry Goods',
    'rice': 'Pantry & Dry Goods',
  };

  /// Looks up a product by [barcode]. Returns null if not found.
  Future<ProductInfo?> lookup(String barcode) async {
    final uri = Uri.parse(
      'https://world.openfoodfacts.org/api/v2/product/$barcode.json'
      '?fields=product_name,brands,categories_tags',
    );

    try {
      final response = await _client.get(
        uri,
        headers: {'User-Agent': 'StockHome/1.0 (grocery tracker)'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 1) return null; // 1 = found

      final product = data['product'] as Map<String, dynamic>?;
      if (product == null) return null;

      final name = (product['product_name'] as String?)?.trim();
      if (name == null || name.isEmpty) return null;

      return ProductInfo(
        name: name,
        category: _guessCategory(product['categories_tags']),
      );
    } catch (_) {
      // Network error, timeout, or bad payload — treat as "not found".
      return null;
    }
  }

  String? _guessCategory(dynamic categoriesTags) {
    if (categoriesTags is! List) return null;
    final tags = categoriesTags
        .whereType<String>()
        .map((t) => t.toLowerCase())
        .toList();
    for (final tag in tags) {
      for (final entry in _categoryHints.entries) {
        if (tag.contains(entry.key)) return entry.value;
      }
    }
    return null;
  }
}
