import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/recipe.dart';
import '../models/recipe_history.dart';

class RecipeConflictException implements Exception {
  const RecipeConflictException();

  @override
  String toString() =>
      'This recipe was changed by another household member. Reload it before saving.';
}

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
    final ref = await _recipes(householdId).add({
      ..._toMap(recipe),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Updates only if the server version still matches the version loaded by
  /// the editor. Prevents silent last-write-wins data loss.
  Future<void> updateRecipe(String householdId, Recipe recipe) async {
    final ref = _recipes(householdId).doc(recipe.id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Recipe no longer exists.');
      final data = snap.data() ?? const <String, dynamic>{};
      final serverUpdated = _dateFrom(data['updatedAt']);
      final expected = recipe.updatedAt;
      if (expected != null &&
          (serverUpdated == null ||
              serverUpdated.millisecondsSinceEpoch !=
                  expected.millisecondsSinceEpoch)) {
        throw const RecipeConflictException();
      }
      tx.update(ref, {
        ..._toMap(recipe),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> deleteRecipe(String householdId, String recipeId) {
    return _recipes(householdId).doc(recipeId).delete();
  }

  Stream<List<RecipeHistoryEntry>> watchHistory(String householdId) {
    return _db
        .collection('households')
        .doc(householdId)
        .collection('recipeHistory')
        .orderBy('cookedAt', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) {
                final data = doc.data();
                return RecipeHistoryEntry(
                  id: doc.id,
                  recipeId: (data['recipeId'] ?? '') as String,
                  recipeName: (data['recipeName'] ?? 'Recipe') as String,
                  cookedAt: _dateFrom(data['cookedAt']) ?? DateTime.now(),
                  cookedBy: data['cookedBy'] as String?,
                );
              })
              .toList(growable: false),
        );
  }

  Future<void> recordCooked({
    required String householdId,
    required Recipe recipe,
    String? cookedBy,
  }) {
    return _db
        .collection('households')
        .doc(householdId)
        .collection('recipeHistory')
        .add({
          'recipeId': recipe.id,
          'recipeName': recipe.name,
          'cookedBy': cookedBy,
          'cookedAt': FieldValue.serverTimestamp(),
        });
  }

  // --- Serialization ---

  static Recipe _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return recipeFromMap(doc.id, data);
  }

  static Map<String, dynamic> _toMap(Recipe r) => recipeToMap(r);

  static DateTime? _dateFrom(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
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
    category: (data['category'] ?? 'Other') as String,
    tags: ((data['tags'] as List?) ?? const []).whereType<String>().toList(),
    updatedAt: recipeDateFrom(data['updatedAt']),
    isDraft: (data['isDraft'] as bool?) ?? false,
  );
}

DateTime? recipeDateFrom(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

/// Pure Recipe -> map conversion (testable without Firestore).
Map<String, dynamic> recipeToMap(Recipe r) {
  return {
    'name': r.name.trim(),
    'description': r.description?.trim(),
    'servings': r.servings,
    'createdBy': r.createdBy,
    'imageUrl': r.imageUrl,
    'category': r.category,
    'tags': r.tags,
    'isDraft': r.isDraft,
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
