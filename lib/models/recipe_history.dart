/// A completed cooking session for a household recipe.
class RecipeHistoryEntry {
  const RecipeHistoryEntry({
    required this.id,
    required this.recipeId,
    required this.recipeName,
    required this.cookedAt,
    this.cookedBy,
  });

  final String id;
  final String recipeId;
  final String recipeName;
  final DateTime cookedAt;
  final String? cookedBy;
}
