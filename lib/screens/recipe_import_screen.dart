import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/grocery_item.dart';
import '../models/recipe_parser.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../theme/app_theme.dart';

/// Paste a recipe's ingredients; see what's in stock vs. missing and add the
/// missing ones to the shopping list in one tap.
class RecipeImportScreen extends StatefulWidget {
  const RecipeImportScreen({super.key});

  @override
  State<RecipeImportScreen> createState() => _RecipeImportScreenState();
}

class _RecipeImportScreenState extends State<RecipeImportScreen> {
  final _controller = TextEditingController();
  bool _analyzed = false;
  List<String> _inStock = const [];
  List<String> _missing = const [];
  final Set<String> _selectedMissing = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Parses pasted recipe text into clean ingredient names, one per line.
  /// Delegates to the pure, unit-tested [parseIngredients] helper.
  List<String> _parseIngredients(String text) => parseIngredients(text);

  void _analyze() {
    final ingredients = _parseIngredients(_controller.text);
    final result = context.read<GroceryProvider>().matchIngredients(
      ingredients,
    );
    setState(() {
      _inStock = result.inStock;
      _missing = result.missing;
      _selectedMissing
        ..clear()
        ..addAll(result.missing); // default: all missing selected
      _analyzed = true;
    });
  }

  Future<void> _addSelected() async {
    final who = context.read<AuthProvider>().resolvedDisplayName;
    final toAdd = _selectedMissing.toList();
    await context.read<GroceryProvider>().addIngredientsToList(
      toAdd,
      updatedBy: who,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('${toAdd.length} ingredients added to shopping list'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final green = AppTheme.statusColor(GroceryStatus.inStock);
    final red = AppTheme.statusColor(GroceryStatus.needsPurchase);

    return Scaffold(
      appBar: AppBar(title: const Text('Add from recipe')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              maxLines: 6,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Paste recipe ingredients',
                hintText: '2 cups rice\n1 onion\n3 tomatoes\n1 tbsp oil\nsalt',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _controller.text.trim().isEmpty ? null : _analyze,
                icon: const Icon(Icons.search),
                label: const Text('Check against inventory'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_analyzed)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (_missing.isNotEmpty) ...[
                    Text(
                      'MISSING — ${_selectedMissing.length} selected',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: red,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final name in _missing)
                      CheckboxListTile(
                        value: _selectedMissing.contains(name),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedMissing.add(name);
                          } else {
                            _selectedMissing.remove(name);
                          }
                        }),
                        title: Text(name),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (_inStock.isNotEmpty) ...[
                    Text(
                      'ALREADY IN STOCK',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: green,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final name in _inStock)
                      ListTile(
                        leading: Icon(Icons.check_circle, color: green),
                        title: Text(name),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                  if (_missing.isEmpty && _inStock.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No ingredients recognised. Try one per line.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _analyzed && _missing.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _selectedMissing.isEmpty ? null : _addSelected,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(
                    'Add ${_selectedMissing.length} to shopping list',
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
