import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/recipe.dart';

/// Firestore CRUD + streaming for household-shared user recipes.
///
/// Layout: households/{householdId}/recipes/{recipeId}
class RecipeService {
  RecipeService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _recipes(String householdId) {
    return _db.collection('households').doc(householdId).collection('recipes');
  }

  /// Real-time stream of the household's user recipes, ordered by name.
  Stream<List<Recipe>> watchRecipes(String householdId) {
    return _recipes(householdId)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).toList(growable: false));
  }

  Future<String> addRecipe(String householdId, Recipe recipe) async {
    final ref = await _recipes(householdId).add(_toMap(recipe));
    return ref.id;
  }

  Future<void> updateRecipe(String householdId, Recipe recipe) {
    return _recipes(householdId).doc(recipe.id).update(_toMap(recipe));
  }

  Future<void> deleteRecipe(String householdId, String recipeId) {
    return _recipes(householdId).doc(recipeId).delete();
  }

  // --- Serialization ---

  static Recipe _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return recipeFromMap(doc.id, data);
  }

  static Map<String, dynamic> _toMap(Recipe r) => recipeToMap(r);
}

/// Pure map -> Recipe conversion (testable without Firestore).
Recipe recipeFromMap(String id, Map<String, dynamic> data) {
  final ingredients = ((data['ingredients'] as List?) ?? const [])
      .whereType<Map>()
      .map((m) {
        final map = m.cast<String, dynamic>();
        return RecipeIngredient(
          id: (map['id'] ?? '') as String,
          name: (map['name'] ?? '') as String,
          quantity: map['quantity'] as String?,
          unit: map['unit'] as String?,
          prep: map['prep'] as String?,
          optional: (map['optional'] as bool?) ?? false,
        );
      })
      .where((i) => i.id.isNotEmpty && i.name.isNotEmpty)
      .toList();

  final steps = ((data['steps'] as List?) ?? const [])
      .whereType<Map>()
      .map((m) {
        final map = m.cast<String, dynamic>();
        return RecipeStep(
          text: (map['text'] ?? '') as String,
          requiresIngredients:
              ((map['requiresIngredients'] as List?) ?? const [])
                  .whereType<String>()
                  .toList(),
          timerSeconds: (map['timerSeconds'] as num?)?.toInt(),
          optional: (map['optional'] as bool?) ?? false,
        );
      })
      .where((s) => s.text.isNotEmpty)
      .toList();

  return Recipe(
    id: id,
    name: (data['name'] ?? 'Recipe') as String,
    description: data['description'] as String?,
    servings: (data['servings'] as num?)?.toInt(),
    ingredients: ingredients,
    steps: steps,
    isBuiltIn: false,
    createdBy: data['createdBy'] as String?,
    imageUrl: data['imageUrl'] as String?,
  );
}

/// Pure Recipe -> map conversion (testable without Firestore).
Map<String, dynamic> recipeToMap(Recipe r) {
  return {
    'name': r.name.trim(),
    'description': r.description?.trim(),
    'servings': r.servings,
    'createdBy': r.createdBy,
    'imageUrl': r.imageUrl,
    'ingredients': r.ingredients
        .map(
          (i) => {
            'id': i.id,
            'name': i.name,
            'quantity': i.quantity,
            'unit': i.unit,
            'prep': i.prep,
            'optional': i.optional,
          },
        )
        .toList(),
    'steps': r.steps
        .map(
          (s) => {
            'text': s.text,
            'requiresIngredients': s.requiresIngredients,
            'timerSeconds': s.timerSeconds,
            'optional': s.optional,
          },
        )
        .toList(),
  };
}
