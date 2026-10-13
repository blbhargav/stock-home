import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
///
/// Steps can be ticked off (session-only, tracked by content so it survives the
/// dynamic rebuild) and steps with a duration expose an inline countdown timer
/// that fires a local notification on completion.
class RecipeCookScreen extends StatefulWidget {
  const RecipeCookScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  State<RecipeCookScreen> createState() => _RecipeCookScreenState();
}

class _RecipeCookScreenState extends State<RecipeCookScreen>
    with WidgetsBindingObserver {
  Set<String> _selected = {};
  bool _initialized = false;
  int _servings = 1;

  /// Steps the user has ticked off while cooking. Tracked by step key (not
  /// index) so completion survives the dynamic rebuild when ingredients change.
  /// Session-only — never persisted.
  final Set<String> _doneSteps = {};

  /// Active countdowns, keyed by step key → remaining seconds.
  final Map<String, int> _remaining = {};
  final Map<String, Timer> _timers = {};
  final Map<String, DateTime> _endsAt = {};
  final Map<String, String> _timerTexts = {};
  final Set<String> _completedTimerKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reconcileTimers();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _initSelection(Recipe recipe) {
    if (_initialized) return;
    _selected = recipe.defaultSelection;
    _servings = recipe.servings ?? 1;
    _initialized = true;
  }

  /// Stable key for a cook step's done/timer state, combining prep flag + text
  /// so a prep step and a base step with the same wording don't collide.
  String _stepKey(CookStep s) => '${s.isPrep ? 'p' : 's'}:${s.text}';

  void _startTimer(String key, int seconds, String stepText) {
    _timers[key]?.cancel();
    final endsAt = DateTime.now().add(Duration(seconds: seconds));
    _endsAt[key] = endsAt;
    _timerTexts[key] = stepText;
    _completedTimerKeys.remove(key);
    setState(() => _remaining[key] = seconds);
    unawaited(
      NotificationService.instance.scheduleCookingTimer(
        timerKey: key,
        stepText: stepText,
        endsAt: endsAt,
      ),
    );
    _timers[key] = Timer.periodic(const Duration(seconds: 1), (timer) {
      final end = _endsAt[key];
      final left = end == null ? 0 : end.difference(DateTime.now()).inSeconds;
      if (left <= 0) {
        timer.cancel();
        _timers.remove(key);
        _finishTimer(key, stepText, showNotification: true);
      } else if (mounted) {
        setState(() => _remaining[key] = left);
      }
    });
  }

  void _finishTimer(
    String key,
    String stepText, {
    required bool showNotification,
  }) {
    _endsAt.remove(key);
    _timerTexts.remove(key);
    if (mounted) setState(() => _remaining.remove(key));
    if (!_completedTimerKeys.add(key)) return;
    if (showNotification) {
      unawaited(NotificationService.instance.showTimerComplete(stepText));
    }
    HapticFeedback.vibrate();
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
  }

  void _reconcileTimers() {
    final now = DateTime.now();
    for (final entry in _endsAt.entries.toList()) {
      final left = entry.value.difference(now).inSeconds;
      final key = entry.key;
      final text = _timerTexts[key] ?? 'Cooking step';
      if (left <= 0) {
        _timers[key]?.cancel();
        _timers.remove(key);
        _finishTimer(key, text, showNotification: false);
      } else {
        if (mounted) setState(() => _remaining[key] = left);
        if (!_timers.containsKey(key)) {
          _timers[key] = Timer.periodic(const Duration(seconds: 1), (timer) {
            final end = _endsAt[key];
            final remaining = end == null
                ? 0
                : end.difference(DateTime.now()).inSeconds;
            if (remaining <= 0) {
              timer.cancel();
              _timers.remove(key);
              _finishTimer(key, text, showNotification: false);
            } else if (mounted) {
              setState(() => _remaining[key] = remaining);
            }
          });
        }
      }
    }
  }

  void _cancelTimer(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
    _endsAt.remove(key);
    _timerTexts.remove(key);
    _completedTimerKeys.remove(key);
    unawaited(NotificationService.instance.cancelCookingTimer(key));
    if (mounted) setState(() => _remaining.remove(key));
  }

  void _toggleStep(CookStep step) {
    HapticFeedback.selectionClick();
    setState(() {
      final key = _stepKey(step);
      if (!_doneSteps.add(key)) _doneSteps.remove(key);
    });
  }

  void _toggleIngredient(String id, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  Future<void> _addMissingToList(BuildContext context, Recipe recipe) async {
    final grocery = context.read<GroceryProvider>();
    final who = context.read<AuthProvider>().resolvedDisplayName;
    final messenger = ScaffoldMessenger.of(context);

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

  Future<void> _recordCooked(Recipe recipe) async {
    final provider = context.read<RecipeProvider>();
    final who = context.read<AuthProvider>().resolvedDisplayName;
    await provider.recordCooked(recipe, cookedBy: who);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cooking session saved to history.')),
    );
  }

  /// Whether any selected ingredient is missing from inventory.
  bool _hasMissing(BuildContext context, Recipe recipe) {
    final grocery = context.read<GroceryProvider>();
    for (final ing in recipe.ingredients) {
      if (!_selected.contains(ing.id)) continue;
      final match = grocery.findInventoryMatch(ing.name);
      if (match == null || match.status == GroceryStatus.needsPurchase) {
        return true;
      }
    }
    return false;
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
        final scheme = Theme.of(context).colorScheme;
        final doneCount = steps
            .where((s) => _doneSteps.contains(_stepKey(s)))
            .length;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: _buildAppBar(context, recipe, scheme),
          body: CustomScrollView(
            slivers: [
              _HeroHeader(recipe: recipe),

              SliverToBoxAdapter(
                child: _ProgressBanner(done: doneCount, total: steps.length),
              ),

              SliverToBoxAdapter(
                child: _ServingsControl(
                  servings: _servings,
                  onChanged: (value) => setState(() => _servings = value),
                ),
              ),

              SliverToBoxAdapter(
                child: _SectionHeader(
                  icon: Icons.checklist_rounded,
                  title: 'Ingredients',
                  subtitle: 'Tap to select what you\'re using',
                ),
              ),

              SliverList.separated(
                itemCount: recipe.ingredients.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 72,
                  endIndent: 20,
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
                itemBuilder: (context, i) {
                  final ing = recipe.ingredients[i];
                  final match = context
                      .watch<GroceryProvider>()
                      .findInventoryMatch(ing.name);
                  return _IngredientRow(
                    ingredient: ing,
                    quantityLabel: [
                      scaledQuantityLabel(
                        ing.quantity,
                        _servings / (recipe.servings ?? 1),
                      ),
                      ing.unit ?? '',
                    ].where((part) => part.isNotEmpty).join(' '),
                    isSelected: _selected.contains(ing.id),
                    match: match,
                    onToggle: () =>
                        _toggleIngredient(ing.id, !_selected.contains(ing.id)),
                    onOpenInventory: match == null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ItemDetailScreen(itemId: match.id),
                            ),
                          ),
                  );
                },
              ),

              SliverToBoxAdapter(
                child: _ShoppingListButton(
                  hasMissing: _hasMissing(context, recipe),
                  onPressed: () => _addMissingToList(context, recipe),
                ),
              ),

              SliverToBoxAdapter(
                child: _SectionHeader(
                  icon: Icons.menu_book_rounded,
                  title: 'Method',
                  subtitle: steps.isEmpty
                      ? 'Select ingredients to see the steps'
                      : '$doneCount of ${steps.length} done',
                  trailing: steps.isNotEmpty && doneCount == steps.length
                      ? const _DoneAllBadge()
                      : null,
                ),
              ),

              if (steps.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Select some ingredients to see the steps.'),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: steps.length,
                  itemBuilder: (context, index) {
                    final step = steps[index];
                    final key = _stepKey(step);
                    final secs = step.timerSeconds;
                    return _StepCard(
                      number: index + 1,
                      step: step,
                      isDone: _doneSteps.contains(key),
                      remaining: _remaining[key],
                      isTimerRunning: _timers.containsKey(key),
                      onTap: () => _toggleStep(step),
                      onStartTimer: (secs != null && secs > 0)
                          ? () => _startTimer(key, secs, step.text)
                          : null,
                      onCancelTimer: () => _cancelTimer(key),
                    );
                  },
                ),
              if (steps.isNotEmpty && doneCount == steps.length)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: FilledButton.icon(
                      onPressed: () => _recordCooked(recipe),
                      icon: const Icon(Icons.history),
                      label: const Text('Finish and save to history'),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    Recipe recipe,
    ColorScheme scheme,
  ) {
    Widget circle(IconData icon) => Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: scheme.onSurface),
    );

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        tooltip: 'Back',
        icon: circle(Icons.arrow_back),
        onPressed: () => Navigator.maybePop(context),
      ),
      actions: [
        if (!recipe.isBuiltIn)
          IconButton(
            tooltip: 'Edit recipe',
            icon: circle(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RecipeEditScreen(existing: recipe),
              ),
            ),
          ),
        if (recipe.isBuiltIn)
          IconButton(
            tooltip: 'Save an editable copy',
            icon: circle(Icons.copy_all_outlined),
            onPressed: () => _saveCopy(context, recipe),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Future<void> _saveCopy(BuildContext context, Recipe recipe) async {
    final provider = context.read<RecipeProvider>();
    final who = context.read<AuthProvider>().resolvedDisplayName;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final newId = await provider.duplicateRecipe(recipe, createdBy: who);
    if (newId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save a copy.')),
      );
      return;
    }
    // Replace this read-only built-in view with the editable copy.
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => RecipeCookScreen(recipeId: newId)),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Saved an editable copy to your recipes'),
        ),
      );
  }
}

// ---------------------------------------------------------------------------
// Hero header
// ---------------------------------------------------------------------------

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final hasImage = recipe.imageUrl != null && recipe.imageUrl!.isNotEmpty;

    return SliverToBoxAdapter(
      child: Container(
        decoration: hasImage
            ? null
            : BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryContainer,
                    scheme.secondaryContainer.withValues(alpha: 0.6),
                    scheme.surface,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
        child: Stack(
          children: [
            if (hasImage) ...[
              Positioned.fill(
                child: Image.network(
                  recipe.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 64, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        recipe.isBuiltIn ? 'Built-in recipe' : 'My recipe',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      recipe.name,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: hasImage ? Colors.white : scheme.onSurface,
                        letterSpacing: -0.5,
                        height: 1.15,
                      ),
                    ),
                    if (recipe.description != null &&
                        recipe.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        recipe.description!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: hasImage
                              ? Colors.white.withValues(alpha: 0.9)
                              : scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (recipe.servings != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_alt_outlined,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${recipe.servings} serving${recipe.servings! > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Servings control
// ---------------------------------------------------------------------------

class _ServingsControl extends StatelessWidget {
  const _ServingsControl({required this.servings, required this.onChanged});

  final int servings;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: [
          Icon(Icons.people_alt_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            'Servings',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Decrease servings',
            onPressed: servings > 1 ? () => onChanged(servings - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(
            '$servings',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          IconButton(
            tooltip: 'Increase servings',
            onPressed: servings < 50 ? () => onChanged(servings + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress banner
// ---------------------------------------------------------------------------

class _ProgressBanner extends StatelessWidget {
  const _ProgressBanner({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = total == 0 ? 0.0 : done / total;
    final allDone = done == total && total > 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allDone
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allDone
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allDone ? Icons.check_circle_rounded : Icons.timer_outlined,
                size: 18,
                color: allDone ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                allDone
                    ? 'All done — enjoy your meal!'
                    : total == 0
                    ? 'No steps yet'
                    : '$done of $total steps done',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: allDone ? scheme.primary : scheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: allDone ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              builder: (_, val, _) => LinearProgressIndicator(
                value: val,
                minHeight: 6,
                backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ingredient row
// ---------------------------------------------------------------------------

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.ingredient,
    required this.isSelected,
    required this.match,
    required this.quantityLabel,
    required this.onToggle,
    this.onOpenInventory,
  });

  final RecipeIngredient ingredient;
  final bool isSelected;
  final GroceryItem? match;
  final String quantityLabel;
  final VoidCallback onToggle;
  final VoidCallback? onOpenInventory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ing = ingredient;
    final qtyStr = quantityLabel;

    return Semantics(
      label:
          '${ing.name}${qtyStr.isNotEmpty ? ', $qtyStr' : ''}'
          '${ing.optional ? ', optional' : ''}. '
          '${isSelected ? 'Selected' : 'Not selected'}.',
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? scheme.primary : scheme.outlineVariant,
                    width: 1.8,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: scheme.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            ing.name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (qtyStr.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            qtyStr,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (ing.optional) ...[
                          const SizedBox(width: 8),
                          const _OptionalBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (ing.prep != null && ing.prep!.trim().isNotEmpty)
                          _PrepHint(text: 'needs ${ing.prep}'),
                        if (match != null)
                          _InventoryChip(
                            status: match!.status,
                            onTap: onOpenInventory,
                          )
                        else
                          Text(
                            'not in inventory',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionalBadge extends StatelessWidget {
  const _OptionalBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'Optional',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: scheme.onSecondaryContainer,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _PrepHint extends StatelessWidget {
  const _PrepHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cut_outlined,
          size: 11,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tappable chip showing a matched inventory item's status; opens its detail.
class _InventoryChip extends StatelessWidget {
  const _InventoryChip({required this.status, this.onTap});

  final GroceryStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(status);
    final icon = switch (status) {
      GroceryStatus.inStock => Icons.check_circle_outline_rounded,
      GroceryStatus.runningLow => Icons.warning_amber_rounded,
      GroceryStatus.needsPurchase => Icons.add_shopping_cart_rounded,
      GroceryStatus.purchased => Icons.shopping_bag_outlined,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              status.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (onTap != null) const SizedBox(width: 2),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 11,
                color: color.withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shopping list button
// ---------------------------------------------------------------------------

class _ShoppingListButton extends StatelessWidget {
  const _ShoppingListButton({
    required this.hasMissing,
    required this.onPressed,
  });

  final bool hasMissing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: FilledButton.tonalIcon(
        onPressed: hasMissing ? onPressed : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: hasMissing
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          foregroundColor: hasMissing
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
        icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
        label: Text(
          hasMissing
              ? 'Add missing to shopping list'
              : 'All ingredients in stock',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step card
// ---------------------------------------------------------------------------

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.step,
    required this.isDone,
    required this.onTap,
    this.remaining,
    this.isTimerRunning = false,
    this.onStartTimer,
    this.onCancelTimer,
  });

  final int number;
  final CookStep step;
  final bool isDone;
  final VoidCallback onTap;
  final int? remaining;
  final bool isTimerRunning;
  final VoidCallback? onStartTimer;
  final VoidCallback? onCancelTimer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPrep = step.isPrep;
    final hasTimer = (step.timerSeconds ?? 0) > 0;

    return Semantics(
      label:
          'Step $number. ${isPrep ? 'Prep. ' : ''}${step.text}. '
          '${isDone ? 'Done' : 'Not done'}.',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Material(
          color: isDone
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StepBubble(number: number, isDone: isDone, isPrep: isPrep),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isPrep) ...[
                          Text(
                            'PREP',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: scheme.tertiary,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                        if (step.optional) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'OPTIONAL',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                        ],
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: theme.textTheme.bodyMedium!.copyWith(
                            color: isDone
                                ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                                : scheme.onSurface,
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            decorationColor: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                          child: Text(step.text),
                        ),
                        if (hasTimer && !isDone) ...[
                          const SizedBox(height: 10),
                          _TimerRow(
                            seconds: step.timerSeconds!,
                            remaining: remaining,
                            isRunning: isTimerRunning,
                            onStart: onStartTimer,
                            onCancel: onCancelTimer,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepBubble extends StatelessWidget {
  const _StepBubble({
    required this.number,
    required this.isDone,
    required this.isPrep,
  });

  final int number;
  final bool isDone;
  final bool isPrep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = isPrep ? scheme.tertiary : scheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone
            ? scheme.primary
            : accent.withValues(alpha: isPrep ? 0.18 : 0.15),
        border: isDone
            ? null
            : Border.all(color: accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Center(
        child: isDone
            ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
            : Text(
                '$number',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
      ),
    );
  }
}

class _TimerRow extends StatelessWidget {
  const _TimerRow({
    required this.seconds,
    required this.isRunning,
    this.remaining,
    this.onStart,
    this.onCancel,
  });

  final int seconds;
  final int? remaining;
  final bool isRunning;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _fmtDuration(int s) {
    if (s >= 3600) {
      final h = s ~/ 3600;
      final m = (s % 3600) ~/ 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    if (s >= 60) {
      final m = s ~/ 60;
      final sec = s % 60;
      return sec > 0 ? '${m}m ${sec}s' : '${m}m';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!isRunning) {
      return GestureDetector(
        onTap: onStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_outlined, size: 14, color: scheme.primary),
              const SizedBox(width: 5),
              Text(
                'Start ${_fmtDuration(seconds)} timer',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final rem = remaining ?? seconds;
    final progress = seconds == 0 ? 0.0 : 1.0 - (rem / seconds);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 800),
                builder: (_, val, _) => CircularProgressIndicator(
                  value: val,
                  strokeWidth: 3,
                  backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _fmt(rem),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: scheme.primary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 3),
                Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DoneAllBadge extends StatelessWidget {
  const _DoneAllBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            'All done!',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
