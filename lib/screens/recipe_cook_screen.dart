import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../providers/recipe_provider.dart';
import 'recipe_edit_screen.dart';

/// Interactive cooking screen. The user ticks the ingredients they're using;
/// the method below updates live — prep steps appear for ingredients that need
/// preprocessing, and steps for unticked optional ingredients are hidden.
class RecipeCookScreen extends StatefulWidget {
  const RecipeCookScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  State<RecipeCookScreen> createState() => _RecipeCookScreenState();
}

class _RecipeCookScreenState extends State<RecipeCookScreen> {
  Set<String> _selected = {};
  bool _initialized = false;

  void _initSelection(Recipe recipe) {
    if (_initialized) return;
    _selected = recipe.defaultSelection;
    _initialized = true;
  }

  Future<void> _addMissingToList(BuildContext context, Recipe recipe) async {
    final grocery = context.read<GroceryProvider>();
    final who = context.read<AuthProvider>().resolvedDisplayName;
    final messenger = ScaffoldMessenger.of(context);

    // Names of selected ingredients, matched against current in-stock items.
    final selectedNames = recipe.ingredients
        .where((i) => _selected.contains(i.id))
        .map((i) => i.name)
        .toList();
    final result = grocery.matchIngredients(selectedNames);
    if (result.missing.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('You already have all selected ingredients.'),
        ),
      );
      return;
    }
    await grocery.addIngredientsToList(result.missing, updatedBy: who);
    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${result.missing.length} missing ingredient(s) added to shopping list',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RecipeProvider>(
      builder: (context, provider, _) {
        final recipe = provider.byId(widget.recipeId);
        if (recipe == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Recipe not found.')),
          );
        }
        _initSelection(recipe);

        final steps = buildCookSteps(recipe, _selected);
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(recipe.name),
            actions: [
              if (!recipe.isBuiltIn)
                IconButton(
                  tooltip: 'Edit recipe',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecipeEditScreen(existing: recipe),
                    ),
                  ),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (recipe.description != null &&
                  recipe.description!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    recipe.description!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),

              _SectionHeader(
                icon: Icons.checklist,
                title: 'Ingredients',
                subtitle: 'Tick what you\'re using',
              ),
              for (final ing in recipe.ingredients)
                _IngredientTile(
                  ingredient: ing,
                  selected: _selected.contains(ing.id),
                  onChanged: (v) => setState(() {
                    if (v) {
                      _selected.add(ing.id);
                    } else {
                      _selected.remove(ing.id);
                    }
                  }),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: () => _addMissingToList(context, recipe),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Add missing to shopping list'),
                ),
              ),

              _SectionHeader(
                icon: Icons.format_list_numbered,
                title: 'Method',
                subtitle: '${steps.length} steps',
              ),
              if (steps.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Select some ingredients to see the steps.'),
                )
              else
                for (var i = 0; i < steps.length; i++)
                  _StepTile(number: i + 1, step: steps[i]),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientTile extends StatelessWidget {
  const _IngredientTile({
    required this.ingredient,
    required this.selected,
    required this.onChanged,
  });

  final RecipeIngredient ingredient;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amount = ingredient.amountLabel;

    return CheckboxListTile(
      value: selected,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Row(
        children: [
          Flexible(child: Text(ingredient.name)),
          if (amount.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              amount,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (ingredient.optional) ...[
            const SizedBox(width: 8),
            _Pill(label: 'Optional', color: scheme.tertiary),
          ],
        ],
      ),
      subtitle: (ingredient.prep != null && ingredient.prep!.trim().isNotEmpty)
          ? Text('needs ${ingredient.prep}')
          : null,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.number, required this.step});

  final int number;
  final CookStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = step.isPrep ? scheme.tertiary : scheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text(
              '$number',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (step.isPrep)
                  Text(
                    'PREP',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                Text(step.text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
