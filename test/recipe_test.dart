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

  group('servings scaling', () {
    test('scales numeric, fraction, and unicode quantities', () {
      expect(scaledQuantityLabel('2', 2), '4');
      expect(scaledQuantityLabel('1/2', 2), '1');
      expect(scaledQuantityLabel('½', 3), '1.5');
      expect(scaledQuantityLabel('to taste', 2), 'to taste');
      expect(scaledQuantityLabel('', 2), '');
    });
  });

  group('recipe serialization round-trip', () {
    test('toMap -> fromMap preserves fields', () {
      final original = _sample().copyWith(
        createdBy: 'Bhargav',
        category: 'Breakfast',
        tags: ['quick', 'egg'],
      );
      final map = recipeToMap(original);
      final restored = recipeFromMap('r1', map);

      expect(restored.name, original.name);
      expect(restored.servings, original.servings);
      expect(restored.createdBy, 'Bhargav');
      expect(restored.category, 'Breakfast');
      expect(restored.tags, ['quick', 'egg']);
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

  group('step timers', () {
    test('parseDurationSeconds handles minutes, seconds, hours', () {
      expect(parseDurationSeconds('cook for 5 minutes'), 300);
      expect(parseDurationSeconds('simmer 90 seconds'), 90);
      expect(parseDurationSeconds('rest for 1 hour'), 3600);
      expect(parseDurationSeconds('fry 2 min'), 120);
      expect(parseDurationSeconds('wait 30 sec'), 30);
    });

    test('parseDurationSeconds takes the lower bound of a range', () {
      expect(parseDurationSeconds('cook for 12-15 min'), 720);
      expect(parseDurationSeconds('about 12–15 minutes'), 720); // en dash
    });

    test('parseDurationSeconds returns null when no duration present', () {
      expect(parseDurationSeconds('stir well and serve'), isNull);
      expect(parseDurationSeconds(''), isNull);
    });

    test('stepTimerSeconds prefers explicit value over text', () {
      const step = RecipeStep(text: 'cook for 5 minutes', timerSeconds: 600);
      expect(stepTimerSeconds(step), 600);
    });

    test('stepTimerSeconds falls back to parsing the text', () {
      const step = RecipeStep(text: 'cook for 5 minutes');
      expect(stepTimerSeconds(step), 300);
    });

    test('cook steps carry a timer, prep steps do not', () {
      const recipe = Recipe(
        id: 'r',
        name: 'Timed',
        ingredients: [
          RecipeIngredient(id: 'rice', name: 'Rice', prep: 'rinsed'),
        ],
        steps: [
          RecipeStep(
            text: 'Boil for 10 minutes.',
            requiresIngredients: ['rice'],
          ),
        ],
      );
      final steps = buildCookSteps(recipe, {'rice'});
      final prep = steps.firstWhere((s) => s.isPrep);
      final cook = steps.firstWhere((s) => !s.isPrep);
      expect(prep.timerSeconds, isNull);
      expect(cook.timerSeconds, 600);
    });

    test('timerSeconds survives a serialization round-trip', () {
      const original = Recipe(
        id: 'r',
        name: 'T',
        ingredients: [RecipeIngredient(id: 'a', name: 'A')],
        steps: [RecipeStep(text: 'Step', timerSeconds: 420)],
      );
      final restored = recipeFromMap('r', recipeToMap(original));
      expect(restored.steps.first.timerSeconds, 420);
    });
  });

  group('optional steps', () {
    test(
      'optional flag propagates into cook steps; prep steps are not optional',
      () {
        const recipe = Recipe(
          id: 'r',
          name: 'Opt',
          ingredients: [
            RecipeIngredient(id: 'rice', name: 'Rice', prep: 'rinsed'),
          ],
          steps: [
            RecipeStep(text: 'Boil the rice.', requiresIngredients: ['rice']),
            RecipeStep(text: 'Garnish before serving.', optional: true),
          ],
        );
        final steps = buildCookSteps(recipe, {'rice'});
        final prep = steps.firstWhere((s) => s.isPrep);
        final garnish = steps.firstWhere((s) => s.text.startsWith('Garnish'));
        final boil = steps.firstWhere((s) => s.text.startsWith('Boil'));
        expect(prep.optional, isFalse);
        expect(boil.optional, isFalse);
        expect(garnish.optional, isTrue);
      },
    );

    test('optional steps are still shown (always visible)', () {
      const recipe = Recipe(
        id: 'r',
        name: 'Opt',
        ingredients: [RecipeIngredient(id: 'a', name: 'A')],
        steps: [RecipeStep(text: 'Optional garnish.', optional: true)],
      );
      final steps = buildCookSteps(recipe, {'a'});
      expect(steps.where((s) => s.text == 'Optional garnish.').length, 1);
    });

    test('step optional survives a serialization round-trip', () {
      const original = Recipe(
        id: 'r',
        name: 'T',
        ingredients: [RecipeIngredient(id: 'a', name: 'A')],
        steps: [
          RecipeStep(text: 'Required step'),
          RecipeStep(text: 'Optional step', optional: true),
        ],
      );
      final restored = recipeFromMap('r', recipeToMap(original));
      expect(restored.steps[0].optional, isFalse);
      expect(restored.steps[1].optional, isTrue);
    });
  });
}
