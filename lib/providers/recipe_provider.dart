import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/builtin_recipes.dart';
import '../models/recipe.dart';
import '../services/recipe_service.dart';

/// Exposes the combined list of built-in and household (user) recipes, and
/// mutations for user recipes. Mirrors GroceryProvider's household binding.
class RecipeProvider extends ChangeNotifier {
  RecipeProvider({RecipeService? service})
    : _service = service ?? RecipeService();

  final RecipeService _service;

  String? _householdId;
  StreamSubscription<List<Recipe>>? _sub;

  List<Recipe> _userRecipes = [];
  bool _loading = false;

  bool get loading => _loading;

  /// Built-in recipes first, then the household's user recipes.
  List<Recipe> get recipes => [...kBuiltInRecipes, ..._userRecipes];

  List<Recipe> get builtInRecipes => kBuiltInRecipes;
  List<Recipe> get userRecipes => List.unmodifiable(_userRecipes);

  /// Finds a recipe by id across both built-in and user recipes.
  Recipe? byId(String id) {
    for (final r in recipes) {
      if (r.id == id) return r;
    }
    return null;
  }

  void bindHousehold(String? householdId) {
    if (_householdId == householdId) return;
    _householdId = householdId;
    _sub?.cancel();
    _sub = null;
    _userRecipes = [];

    if (householdId == null) {
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();

    _sub = _service.watchRecipes(householdId).listen((list) {
      _userRecipes = list;
      _loading = false;
      notifyListeners();
    });
  }

  Future<String?> addRecipe(Recipe recipe) async {
    final id = _householdId;
    if (id == null) return null;
    return _service.addRecipe(id, recipe);
  }

  Future<void> updateRecipe(Recipe recipe) async {
    final id = _householdId;
    if (id == null) return;
    await _service.updateRecipe(id, recipe);
  }

  Future<void> deleteRecipe(String recipeId) async {
    final id = _householdId;
    if (id == null) return;
    await _service.deleteRecipe(id, recipeId);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
