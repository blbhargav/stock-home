import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../providers/recipe_provider.dart';
import 'recipe_cook_screen.dart';
import 'recipe_edit_screen.dart';

/// Navigates to the create-recipe screen.
void openNewRecipe(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const RecipeEditScreen()));
}

/// The scrollable list of recipes, without a scaffold, so it can be embedded
/// as a tab inside the home screen. Includes a search box that filters by
/// recipe name or any ingredient name.
class RecipesBody extends StatefulWidget {
  const RecipesBody({super.key});

  @override
  State<RecipesBody> createState() => _RecipesBodyState();
}

class _RecipesBodyState extends State<RecipesBody> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// A recipe matches when the query appears in its name or any ingredient name.
  bool _matches(Recipe r, String q) {
    if (q.isEmpty) return true;
    if (r.name.toLowerCase().contains(q)) return true;
    return r.ingredients.any((i) => i.name.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Consumer<RecipeProvider>(
      builder: (context, provider, _) {
        final q = _query.trim().toLowerCase();
        final user = provider.userRecipes.where((r) => _matches(r, q)).toList();
        final builtIn = provider.builtInRecipes
            .where((r) => _matches(r, q))
            .toList();
        final noResults = q.isNotEmpty && user.isEmpty && builtIn.isEmpty;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SearchBar(
                controller: _searchCtrl,
                hintText: 'Search recipes or ingredients…',
                leading: Icon(Icons.search, color: scheme.onSurfaceVariant),
                trailing: [
                  if (_query.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
                ],
                onChanged: (v) => setState(() => _query = v),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                  scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
              ),
            ),
            Expanded(
              child: noResults
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No recipes match "$_query".',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 96),
                      children: [
                        if (user.isNotEmpty) ...[
                          const _SectionLabel('Your recipes'),
                          for (final r in user) _RecipeCard(recipe: r),
                        ],
                        if (builtIn.isNotEmpty) ...[
                          const _SectionLabel('Built-in recipes'),
                          for (final r in builtIn) _RecipeCard(recipe: r),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe});
  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final optionalCount = recipe.ingredients.where((i) => i.optional).length;
    final subtitleParts = <String>[
      '${recipe.ingredients.length} ingredients',
      if (recipe.servings != null) 'serves ${recipe.servings}',
      if (optionalCount > 0) '$optionalCount optional',
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(
            recipe.isBuiltIn ? Icons.menu_book : Icons.restaurant,
            color: scheme.onPrimaryContainer,
          ),
        ),
        title: Text(recipe.name),
        subtitle: Text(subtitleParts.join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecipeCookScreen(recipeId: recipe.id),
          ),
        ),
      ),
    );
  }
}
