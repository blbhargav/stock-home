import 'package:flutter_test/flutter_test.dart';
import 'package:stockhome/models/recipe_parser.dart';

void main() {
  group('parseIngredients', () {
    test('strips bullets, numbers, quantities and units', () {
      const text = '''
2 cups rice
1 onion
- 3 tomatoes
1 tbsp oil
salt
''';
      expect(
        parseIngredients(text),
        ['rice', 'onion', 'tomatoes', 'oil', 'salt'],
      );
    });

    test('handles numbered and bulleted lists', () {
      const text = '1. Rice\n2) Dal\n* Ghee\n• Jeera';
      expect(parseIngredients(text), ['Rice', 'Dal', 'Ghee', 'Jeera']);
    });

    test('drops prep notes after comma or parenthesis', () {
      const text = 'onions, finely chopped\ntomatoes (ripe)';
      expect(parseIngredients(text), ['onions', 'tomatoes']);
    });

    test('de-duplicates case-insensitively, keeping first form', () {
      const text = 'Rice\nrice\nRICE';
      expect(parseIngredients(text), ['Rice']);
    });

    test('ignores blank lines and empty results', () {
      const text = '\n\n2 cups\n   \nflour\n';
      // "2 cups" reduces to empty after stripping qty+unit, so it is dropped.
      expect(parseIngredients(text), ['flour']);
    });

    test('keeps multi-word ingredient names', () {
      const text = '200 g basmati rice\n1 cup toor dal';
      expect(parseIngredients(text), ['basmati rice', 'toor dal']);
    });

    test('handles fractional quantities', () {
      const text = '1/2 cup sugar\n2.5 kg atta';
      expect(parseIngredients(text), ['sugar', 'atta']);
    });

    test('empty input yields empty list', () {
      expect(parseIngredients(''), isEmpty);
    });
  });

  group('matchIngredientNames', () {
    test('separates in-stock from missing', () {
      final result = matchIngredientNames(
        ['rice', 'onion', 'saffron'],
        ['Basmati Rice', 'Onion', 'Oil'],
      );
      expect(result.inStock, ['rice', 'onion']);
      expect(result.missing, ['saffron']);
    });

    test('matches when stock name contains ingredient', () {
      final result = matchIngredientNames(['rice'], ['Basmati Rice 1kg']);
      expect(result.inStock, ['rice']);
      expect(result.missing, isEmpty);
    });

    test('matches when ingredient contains stock name', () {
      final result = matchIngredientNames(['red onions'], ['onion']);
      // "red onions" contains "onion"
      expect(result.inStock, ['red onions']);
    });

    test('is case-insensitive', () {
      final result = matchIngredientNames(['SALT'], ['salt']);
      expect(result.inStock, ['SALT']);
    });

    test('skips blank ingredient names', () {
      final result = matchIngredientNames(['', '  ', 'rice'], ['rice']);
      expect(result.inStock, ['rice']);
      expect(result.missing, isEmpty);
    });

    test('empty stock means everything is missing', () {
      final result = matchIngredientNames(['rice', 'dal'], []);
      expect(result.inStock, isEmpty);
      expect(result.missing, ['rice', 'dal']);
    });
  });
}
