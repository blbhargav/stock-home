import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  bool _favoritesOnly = false;
  String? _categoryFilter;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// A recipe matches when the query appears in its name or any ingredient name.
  bool _matches(Recipe r, String q, RecipeProvider provider) {
    if (_favoritesOnly && !provider.isFavorite(r.id)) return false;
    if (_categoryFilter != null && r.category != _categoryFilter) return false;
    if (q.isEmpty) return true;
    if (r.name.toLowerCase().contains(q)) return true;
    if (r.category.toLowerCase().contains(q)) return true;
    if (r.tags.any((tag) => tag.toLowerCase().contains(q))) return true;
    return r.ingredients.any((i) => i.name.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Consumer<RecipeProvider>(
      builder: (context, provider, _) {
        final q = _query.trim().toLowerCase();
        final all = provider.recipes;
        final categories = all.map((r) => r.category).toSet().toList()..sort();
        final user = provider.userRecipes
            .where((r) => _matches(r, q, provider))
            .toList();
        final builtIn = provider.builtInRecipes
            .where((r) => _matches(r, q, provider))
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
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  FilterChip(
                    label: const Text('Favorites'),
                    avatar: const Icon(Icons.favorite, size: 16),
                    selected: _favoritesOnly,
                    onSelected: (value) =>
                        setState(() => _favoritesOnly = value),
                  ),
                  const SizedBox(width: 8),
                  for (final category in categories) ...[
                    FilterChip(
                      label: Text(category),
                      selected: _categoryFilter == category,
                      onSelected: (value) => setState(
                        () => _categoryFilter = value ? category : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
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
                        if (provider.recentHistory.isNotEmpty) ...[
                          const _SectionLabel('Recently cooked'),
                          for (final entry in provider.recentHistory.take(3))
                            ListTile(
                              leading: const Icon(Icons.history),
                              title: Text(entry.recipeName),
                              subtitle: Text(
                                DateFormat.yMMMd().add_jm().format(
                                  entry.cookedAt,
                                ),
                              ),
                              trailing: const Icon(Icons.replay),
                              onTap: () {
                                if (provider.byId(entry.recipeId) != null) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RecipeCookScreen(
                                        recipeId: entry.recipeId,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                        ],
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
      recipe.category,
      '${recipe.ingredients.length} ingredients',
      if (recipe.servings != null) 'serves ${recipe.servings}',
      if (optionalCount > 0) '$optionalCount optional',
      if (recipe.tags.isNotEmpty) recipe.tags.take(2).join(', '),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: context.read<RecipeProvider>().isFavorite(recipe.id)
                  ? 'Remove favorite'
                  : 'Favorite',
              icon: Icon(
                context.watch<RecipeProvider>().isFavorite(recipe.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: context.watch<RecipeProvider>().isFavorite(recipe.id)
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
              onPressed: () =>
                  context.read<RecipeProvider>().toggleFavorite(recipe.id),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecipeCookScreen(recipeId: recipe.id),
          ),
        ),
      ),
    );
  }
}
