import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/builtin_recipes.dart';
import '../models/recipe.dart';
import '../models/recipe_history.dart';
import '../services/recipe_service.dart';
import '../services/settings_service.dart';

/// Exposes the combined list of built-in and household (user) recipes, and
/// mutations for user recipes. Mirrors GroceryProvider's household binding.
class RecipeProvider extends ChangeNotifier {
  RecipeProvider({RecipeService? service, SettingsService? settings})
    : _service = service ?? RecipeService(),
      _settings = settings ?? SettingsService() {
    _loadFavorites();
  }

  final RecipeService _service;
  final SettingsService _settings;

  String? _householdId;
  StreamSubscription<List<Recipe>>? _sub;
  StreamSubscription<List<RecipeHistoryEntry>>? _historySub;

  List<Recipe> _userRecipes = [];
  List<RecipeHistoryEntry> _history = [];
  final Set<String> _favoriteIds = {};
  bool _loading = false;

  bool get loading => _loading;
  List<RecipeHistoryEntry> get recentHistory => List.unmodifiable(_history);
  bool isFavorite(String recipeId) => _favoriteIds.contains(recipeId);

  Future<void> _loadFavorites() async {
    _favoriteIds
      ..clear()
      ..addAll(await _settings.getFavoriteRecipeIds());
    notifyListeners();
  }

  Future<void> toggleFavorite(String recipeId) async {
    if (!_favoriteIds.add(recipeId)) _favoriteIds.remove(recipeId);
    notifyListeners();
    await _settings.setFavoriteRecipeIds(_favoriteIds);
  }

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
    _historySub?.cancel();
    _sub = null;
    _historySub = null;
    _userRecipes = [];
    _history = [];

    if (householdId == null) {
      _loading = false;
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
    _historySub = _service.watchHistory(householdId).listen((list) {
      _history = list;
      notifyListeners();
    });
  }

  Future<String?> addRecipe(Recipe recipe) async {
    final id = _householdId;
    if (id == null) return null;
    return _service.addRecipe(id, recipe);
  }

  /// Saves an editable household copy of any recipe (built-in or user). The
  /// copy drops the image (not re-uploaded) and marks the creator.
  Future<String?> duplicateRecipe(Recipe source, {String? createdBy}) async {
    final id = _householdId;
    if (id == null) return null;
    // Build explicitly so imageUrl is cleared (copyWith can't set null).
    final copy = Recipe(
      id: 'temp',
      name: '${source.name} (copy)',
      description: source.description,
      servings: source.servings,
      ingredients: source.ingredients,
      steps: source.steps,
      isBuiltIn: false,
      createdBy: createdBy,
      category: source.category,
      tags: source.tags,
      isDraft: false,
    );
    return _service.addRecipe(id, copy);
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

  Future<void> recordCooked(Recipe recipe, {String? cookedBy}) async {
    final id = _householdId;
    if (id == null) return;
    await _service.recordCooked(
      householdId: id,
      recipe: recipe,
      cookedBy: cookedBy,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _historySub?.cancel();
    super.dispose();
  }
}
