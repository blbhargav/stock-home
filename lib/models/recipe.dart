/// Recipe domain model and the pure logic that turns a user's ingredient
/// selection into an ordered list of cooking steps.
///
/// Kept free of Flutter/Firebase imports so it can be unit-tested directly.
/// Firestore (de)serialization lives in RecipeService.
library;

/// A single ingredient in a recipe.
class RecipeIngredient {
  const RecipeIngredient({
    required this.id,
    required this.name,
    this.quantity,
    this.unit,
    this.prep,
    this.optional = false,
  });

  /// Stable identifier used to link steps to this ingredient.
  final String id;

  /// Display name, e.g. "Onion".
  final String name;

  /// Optional display quantity, e.g. "2" or "1/2". Free text so fractions work.
  final String? quantity;

  /// Optional unit, e.g. "cup", "tbsp".
  final String? unit;

  /// Preprocessing needed before cooking, e.g. "finely chopped". When set and
  /// the ingredient is selected, a prep step is generated automatically.
  final String? prep;

  /// When true, the ingredient is unticked by default and any steps that depend
  /// on it are hidden unless the user selects it.
  final bool optional;

  /// A human-readable amount like "2 cup" or "1/2 tsp", or empty when unknown.
  String get amountLabel {
    final q = quantity?.trim() ?? '';
    final u = unit?.trim() ?? '';
    return [q, u].where((s) => s.isNotEmpty).join(' ');
  }

  RecipeIngredient copyWith({
    String? id,
    String? name,
    String? quantity,
    String? unit,
    String? prep,
    bool? optional,
  }) {
    return RecipeIngredient(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      prep: prep ?? this.prep,
      optional: optional ?? this.optional,
    );
  }
}

/// A single cooking instruction. A step is only shown when every ingredient id
/// in [requiresIngredients] has been selected by the user. Steps with no
/// requirements always show.
class RecipeStep {
  const RecipeStep({required this.text, this.requiresIngredients = const []});

  final String text;

  /// Ingredient ids this step depends on. If any is unselected (e.g. an
  /// optional ingredient the user skipped), the step is omitted.
  final List<String> requiresIngredients;
}

/// A recipe: its ingredients and the ordered base steps. Prep steps are not
/// stored — they are derived from the selected ingredients' [prep] values.
class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    this.description,
    this.servings,
    this.ingredients = const [],
    this.steps = const [],
    this.isBuiltIn = false,
    this.createdBy,
  });

  final String id;
  final String name;
  final String? description;
  final int? servings;
  final List<RecipeIngredient> ingredients;
  final List<RecipeStep> steps;

  /// True for curated recipes bundled with the app (not editable/deletable).
  final bool isBuiltIn;

  /// Display name of the household member who created a user recipe.
  final String? createdBy;

  /// Ingredient ids that are selected by default (all required ones).
  Set<String> get defaultSelection =>
      ingredients.where((i) => !i.optional).map((i) => i.id).toSet();

  Recipe copyWith({
    String? id,
    String? name,
    String? description,
    int? servings,
    List<RecipeIngredient>? ingredients,
    List<RecipeStep>? steps,
    bool? isBuiltIn,
    String? createdBy,
  }) {
    return Recipe(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      servings: servings ?? this.servings,
      ingredients: ingredients ?? this.ingredients,
      steps: steps ?? this.steps,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}

/// A step shown to the cook: either an auto-generated prep step or one of the
/// recipe's base steps that survived the ingredient filter.
class CookStep {
  const CookStep({required this.text, required this.isPrep});

  final String text;

  /// True for auto-generated "chop the onion" style preparation steps.
  final bool isPrep;
}

/// Builds the ordered cook steps for a recipe given the user's selected
/// ingredient ids.
///
/// 1. Prep steps come first, one per selected ingredient that has a [prep]
///    value, in the recipe's ingredient order.
/// 2. Then the base steps, excluding any whose required ingredients aren't all
///    selected.
List<CookStep> buildCookSteps(Recipe recipe, Set<String> selectedIds) {
  final steps = <CookStep>[];

  // Prep steps for selected ingredients that need preprocessing.
  for (final ing in recipe.ingredients) {
    if (!selectedIds.contains(ing.id)) continue;
    final prep = ing.prep?.trim();
    if (prep == null || prep.isEmpty) continue;
    steps.add(
      CookStep(
        text: '${_capitalize(prep)} the ${ing.name.toLowerCase()}.',
        isPrep: true,
      ),
    );
  }

  // Base steps, filtered by ingredient selection.
  for (final step in recipe.steps) {
    final allPresent = step.requiresIngredients.every(selectedIds.contains);
    if (allPresent) {
      steps.add(CookStep(text: step.text, isPrep: false));
    }
  }

  return steps;
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
