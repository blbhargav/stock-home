import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../providers/recipe_provider.dart';
import 'recipe_cook_screen.dart';
import 'recipe_edit_screen.dart';

/// Lists built-in and household recipes. Tapping one opens the interactive
/// cook screen; the FAB creates a new user recipe.
class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const RecipeEditScreen())),
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
      ),
      body: Consumer<RecipeProvider>(
        builder: (context, provider, _) {
          if (provider.loading && provider.userRecipes.isEmpty) {
            // Built-ins still show while user recipes load.
          }
          final builtIn = provider.builtInRecipes;
          final user = provider.userRecipes;

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (user.isNotEmpty) ...[
                const _SectionLabel('Your recipes'),
                for (final r in user) _RecipeCard(recipe: r),
              ],
              const _SectionLabel('Built-in recipes'),
              for (final r in builtIn) _RecipeCard(recipe: r),
            ],
          );
        },
      ),
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
