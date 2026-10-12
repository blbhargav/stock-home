import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/grocery_item.dart';
import '../models/recipe.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../providers/recipe_provider.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'item_detail_screen.dart';
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

  /// Steps the user has ticked off while cooking. Tracked by step text (not
  /// index) so completion survives the dynamic rebuild when ingredients change.
  /// Session-only — never persisted.
  final Set<String> _doneSteps = {};

  /// Active countdowns, keyed by step key → remaining seconds.
  final Map<String, int> _remaining = {};
  final Map<String, Timer> _timers = {};

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _startTimer(String key, int seconds, String stepText) {
    _timers[key]?.cancel();
    setState(() => _remaining[key] = seconds);
    _timers[key] = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = (_remaining[key] ?? 0) - 1;
      if (left <= 0) {
        timer.cancel();
        _timers.remove(key);
        if (mounted) {
          setState(() => _remaining.remove(key));
        }
        NotificationService.instance.showTimerComplete(stepText);
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('Timer done: $stepText'),
              ),
            );
        }
      } else {
        if (mounted) setState(() => _remaining[key] = left);
      }
    });
  }

  void _cancelTimer(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
    setState(() => _remaining.remove(key));
  }

  void _initSelection(Recipe recipe) {
    if (_initialized) return;
    _selected = recipe.defaultSelection;
    _initialized = true;
  }

  /// Stable key for a cook step's done-state, combining prep flag + text so a
  /// prep step and a base step with the same wording don't collide.
  String _stepKey(CookStep s) => '${s.isPrep ? 'p' : 's'}:${s.text}';

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
                subtitle: steps.isEmpty
                    ? '0 steps'
                    : '${steps.where((s) => _doneSteps.contains(_stepKey(s))).length} of ${steps.length} done',
              ),
              if (steps.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Select some ingredients to see the steps.'),
                )
              else
                for (var i = 0; i < steps.length; i++)
                  _StepTile(
                    number: i + 1,
                    step: steps[i],
                    done: _doneSteps.contains(_stepKey(steps[i])),
                    remainingSeconds: _remaining[_stepKey(steps[i])],
                    onToggle: () => setState(() {
                      final key = _stepKey(steps[i]);
                      if (!_doneSteps.add(key)) _doneSteps.remove(key);
                    }),
                    onStartTimer: () {
                      final s = steps[i];
                      final secs = s.timerSeconds;
                      if (secs != null && secs > 0) {
                        _startTimer(_stepKey(s), secs, s.text);
                      }
                    },
                    onCancelTimer: () => _cancelTimer(_stepKey(steps[i])),
                  ),
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

    // Link this ingredient to a matching inventory item, if any.
    final match = context.watch<GroceryProvider>().findInventoryMatch(
      ingredient.name,
    );

    final prepText =
        (ingredient.prep != null && ingredient.prep!.trim().isNotEmpty)
        ? 'needs ${ingredient.prep}'
        : null;
    final subtitleText = match == null
        ? [prepText, 'not in inventory'].whereType<String>().join(' · ')
        : prepText;

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
      subtitle: (subtitleText != null && subtitleText.isNotEmpty)
          ? Text(subtitleText)
          : null,
      // Trailing: a tappable chip linking to where the item lives in inventory.
      secondary: match == null
          ? null
          : _InventoryLink(
              item: match,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ItemDetailScreen(itemId: match.id),
                ),
              ),
            ),
    );
  }
}

/// A small tappable chip showing a matched inventory item's status; opens its
/// detail screen (where it's stored, photos, notes, etc.).
class _InventoryLink extends StatelessWidget {
  const _InventoryLink({required this.item, required this.onTap});

  final GroceryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(item.status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              item.status.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: color),
          ],
        ),
      ),
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
  const _StepTile({
    required this.number,
    required this.step,
    required this.done,
    required this.remainingSeconds,
    required this.onToggle,
    required this.onStartTimer,
    required this.onCancelTimer,
  });

  final int number;
  final CookStep step;
  final bool done;
  final int? remainingSeconds;
  final VoidCallback onToggle;
  final VoidCallback onStartTimer;
  final VoidCallback onCancelTimer;

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _fmtDuration(int seconds) {
    if (seconds >= 3600) {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = step.isPrep ? scheme.tertiary : scheme.primary;
    final running = remainingSeconds != null;
    final hasTimer = (step.timerSeconds ?? 0) > 0;

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tappable status circle: step number, or a check when done.
            CircleAvatar(
              radius: 14,
              backgroundColor: done
                  ? scheme.primary
                  : color.withValues(alpha: 0.15),
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(
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
                        color: done ? scheme.onSurfaceVariant : color,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  Text(
                    step.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  if (hasTimer) ...[
                    const SizedBox(height: 6),
                    if (running)
                      _TimerChip(
                        label: _fmt(remainingSeconds!),
                        icon: Icons.stop_circle_outlined,
                        active: true,
                        onTap: onCancelTimer,
                      )
                    else
                      _TimerChip(
                        label:
                            'Start ${_fmtDuration(step.timerSeconds!)} timer',
                        icon: Icons.timer_outlined,
                        active: false,
                        onTap: onStartTimer,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerChip extends StatelessWidget {
  const _TimerChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.error : scheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontFeatures: active
                    ? const [FontFeature.tabularFigures()]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
