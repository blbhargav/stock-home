import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockhome/models/builtin_recipes.dart';
import 'package:stockhome/models/recipe.dart';
import 'package:stockhome/providers/recipe_provider.dart';
import 'package:stockhome/services/recipe_service.dart';

/// In-memory fake of RecipeService — no Firestore. Backs watchRecipes with a
/// broadcast stream and records CRUD calls.
class _FakeRecipeService implements RecipeService {
  final _controller = StreamController<List<Recipe>>.broadcast();
  List<Recipe> current = [];
  int addCount = 0;
  int updateCount = 0;
  int deleteCount = 0;
  Recipe? lastAdded;

  void emit(List<Recipe> recipes) {
    current = recipes;
    _controller.add(recipes);
  }

  @override
  Stream<List<Recipe>> watchRecipes(String householdId) => _controller.stream;

  @override
  Future<String> addRecipe(String householdId, Recipe recipe) async {
    addCount++;
    lastAdded = recipe;
    return 'new_id';
  }

  @override
  Future<void> updateRecipe(String householdId, Recipe recipe) async {
    updateCount++;
  }

  @override
  Future<void> deleteRecipe(String householdId, String recipeId) async {
    deleteCount++;
  }
}

void main() {
  group('RecipeProvider', () {
    late _FakeRecipeService fake;
    late RecipeProvider provider;

    setUp(() {
      fake = _FakeRecipeService();
      provider = RecipeProvider(service: fake);
    });

    tearDown(() => provider.dispose());

    test('exposes built-in recipes before binding', () {
      expect(provider.builtInRecipes, kBuiltInRecipes);
      expect(provider.userRecipes, isEmpty);
      expect(provider.recipes.length, kBuiltInRecipes.length);
    });

    test('combines built-in + user recipes after a stream emission', () async {
      provider.bindHousehold('h1');
      fake.emit([
        const Recipe(id: 'u1', name: 'User One'),
        const Recipe(id: 'u2', name: 'User Two'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(provider.userRecipes.length, 2);
      expect(provider.recipes.length, kBuiltInRecipes.length + 2);
      // Built-ins come first, user recipes after.
      expect(provider.recipes.first.id, kBuiltInRecipes.first.id);
      expect(provider.recipes.last.id, 'u2');
    });

    test('byId finds both built-in and user recipes', () async {
      provider.bindHousehold('h1');
      fake.emit([const Recipe(id: 'u1', name: 'User One')]);
      await Future<void>.delayed(Duration.zero);

      expect(provider.byId(kBuiltInRecipes.first.id), isNotNull);
      expect(provider.byId('u1')?.name, 'User One');
      expect(provider.byId('nope'), isNull);
    });

    test('addRecipe is a no-op without a bound household', () async {
      final id = await provider.addRecipe(const Recipe(id: 't', name: 'X'));
      expect(id, isNull);
      expect(fake.addCount, 0);
    });

    test('addRecipe delegates to the service once bound', () async {
      provider.bindHousehold('h1');
      final id = await provider.addRecipe(const Recipe(id: 't', name: 'X'));
      expect(id, 'new_id');
      expect(fake.addCount, 1);
    });

    test(
      'duplicateRecipe clones a built-in into an editable user recipe',
      () async {
        provider.bindHousehold('h1');
        final source = kBuiltInRecipes.first;
        final id = await provider.duplicateRecipe(source, createdBy: 'Bhargav');

        expect(id, 'new_id');
        expect(fake.addCount, 1);
        final copy = fake.lastAdded!;
        expect(copy.isBuiltIn, isFalse);
        expect(copy.name, '${source.name} (copy)');
        expect(copy.createdBy, 'Bhargav');
        expect(copy.imageUrl, isNull);
        // Ingredients and steps are carried over.
        expect(copy.ingredients.length, source.ingredients.length);
        expect(copy.steps.length, source.steps.length);
      },
    );

    test('rebinding to a new household clears user recipes', () async {
      provider.bindHousehold('h1');
      fake.emit([const Recipe(id: 'u1', name: 'User One')]);
      await Future<void>.delayed(Duration.zero);
      expect(provider.userRecipes, isNotEmpty);

      provider.bindHousehold('h2');
      expect(provider.userRecipes, isEmpty);
    });

    test(
      'unbinding (null household) clears recipes and stops loading',
      () async {
        provider.bindHousehold('h1');
        provider.bindHousehold(null);
        expect(provider.userRecipes, isEmpty);
        expect(provider.loading, isFalse);
      },
    );
  });
}
