import 'package:flutter_test/flutter_test.dart';
import 'package:stockhome/models/recipe.dart';
import 'package:stockhome/services/recipe_service.dart';

Recipe _sample() => const Recipe(
  id: 'r1',
  name: 'Test dish',
  servings: 2,
  ingredients: [
    RecipeIngredient(id: 'oil', name: 'Oil', quantity: '1', unit: 'tbsp'),
    RecipeIngredient(id: 'onion', name: 'Onion', prep: 'finely chopped'),
    RecipeIngredient(id: 'peas', name: 'Peas', optional: true),
    RecipeIngredient(
      id: 'coriander',
      name: 'Coriander',
      prep: 'chopped',
      optional: true,
    ),
  ],
  steps: [
    RecipeStep(text: 'Heat the oil.', requiresIngredients: ['oil']),
    RecipeStep(text: 'Fry the onion.', requiresIngredients: ['onion']),
    RecipeStep(text: 'Add peas and stir.', requiresIngredients: ['peas']),
    RecipeStep(text: 'Cook for 5 minutes.'),
    RecipeStep(
      text: 'Garnish with coriander.',
      requiresIngredients: ['coriander'],
    ),
  ],
);

void main() {
  group('defaultSelection', () {
    test('includes required ingredients and excludes optional ones', () {
      final sel = _sample().defaultSelection;
      expect(sel, {'oil', 'onion'});
      expect(sel.contains('peas'), isFalse);
      expect(sel.contains('coriander'), isFalse);
    });
  });

  group('buildCookSteps', () {
    test('default selection: prep steps + non-optional steps only', () {
      final recipe = _sample();
      final steps = buildCookSteps(recipe, recipe.defaultSelection);
      final texts = steps.map((s) => s.text).toList();

      // Prep step for onion appears, auto-generated and marked as prep.
      expect(texts.first, 'Finely chopped the onion.');
      expect(steps.first.isPrep, isTrue);

      // Optional steps (peas, coriander) are hidden.
      expect(texts.any((t) => t.contains('peas')), isFalse);
      expect(texts.any((t) => t.contains('coriander')), isFalse);

      // Required and no-requirement steps are present.
      expect(texts, contains('Heat the oil.'));
      expect(texts, contains('Fry the onion.'));
      expect(texts, contains('Cook for 5 minutes.'));
    });

    test('selecting an optional ingredient reveals its step and prep', () {
      final recipe = _sample();
      final sel = {...recipe.defaultSelection, 'coriander'};
      final steps = buildCookSteps(recipe, sel);
      final texts = steps.map((s) => s.text).toList();

      // Coriander prep step is auto-added.
      expect(texts, contains('Chopped the coriander.'));
      // Coriander cooking step now shows.
      expect(texts, contains('Garnish with coriander.'));
      // Peas still hidden.
      expect(texts.any((t) => t.contains('peas')), isFalse);
    });

    test('optional ingredient without prep adds only its step', () {
      final recipe = _sample();
      final sel = {...recipe.defaultSelection, 'peas'};
      final steps = buildCookSteps(recipe, sel);
      final texts = steps.map((s) => s.text).toList();
      expect(texts, contains('Add peas and stir.'));
      // Peas has no prep, so no extra prep step for it.
      expect(texts.where((t) => t.toLowerCase().contains('peas')).length, 1);
    });

    test('deselecting a required ingredient hides its step', () {
      final recipe = _sample();
      final sel = {'onion'}; // no oil
      final steps = buildCookSteps(recipe, sel);
      final texts = steps.map((s) => s.text).toList();
      expect(texts.any((t) => t.contains('oil')), isFalse);
      expect(texts, contains('Fry the onion.'));
    });

    test('prep steps come before method steps', () {
      final recipe = _sample();
      final steps = buildCookSteps(recipe, recipe.defaultSelection);
      final firstNonPrep = steps.indexWhere((s) => !s.isPrep);
      final lastPrep = steps.lastIndexWhere((s) => s.isPrep);
      expect(lastPrep, lessThan(firstNonPrep));
    });
  });

  group('recipe serialization round-trip', () {
    test('toMap -> fromMap preserves fields', () {
      final original = _sample().copyWith(createdBy: 'Bhargav');
      final map = recipeToMap(original);
      final restored = recipeFromMap('r1', map);

      expect(restored.name, original.name);
      expect(restored.servings, original.servings);
      expect(restored.createdBy, 'Bhargav');
      expect(restored.ingredients.length, original.ingredients.length);
      expect(restored.ingredients[1].prep, 'finely chopped');
      expect(restored.ingredients[2].optional, isTrue);
      expect(restored.steps.length, original.steps.length);
      expect(restored.steps[2].requiresIngredients, ['peas']);
      // Restored user recipes are never built-in.
      expect(restored.isBuiltIn, isFalse);
    });

    test('fromMap tolerates missing/garbage fields', () {
      final restored = recipeFromMap('x', {
        'name': 'Minimal',
        'ingredients': [
          {'id': 'a', 'name': 'A'},
          {'garbage': true}, // dropped (no id/name)
        ],
        'steps': [
          {'text': 'Do a thing'},
          {'nope': 1}, // dropped (no text)
        ],
      });
      expect(restored.name, 'Minimal');
      expect(restored.ingredients.length, 1);
      expect(restored.steps.length, 1);
      expect(restored.ingredients.first.optional, isFalse);
    });
  });
}
