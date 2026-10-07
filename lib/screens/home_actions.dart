import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/grocery_categories.dart';
import '../models/grocery_item.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import 'grocery_form_screen.dart';
import 'item_detail_screen.dart';

/// Shared, context-based grocery actions used across the home tabs.
///
/// These were previously private methods on the HomeScreen state reached via
/// `findAncestorStateOfType`. Extracting them here lets the tab widgets live in
/// their own files and call the actions directly, without coupling to the
/// HomeScreen state.
class HomeActions {
  const HomeActions._();

  /// Opens the add/edit form, optionally pre-filled with [existing].
  static void openForm(BuildContext context, {GroceryItem? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GroceryFormScreen(existing: existing)),
    );
  }

  /// Opens the read-only item detail screen.
  static void openDetail(BuildContext context, GroceryItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: item.id)),
    );
  }

  /// Confirms and deletes an item, with an undo snackbar.
  static Future<void> confirmDelete(
    BuildContext context,
    GroceryItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete grocery?'),
        content: Text('Remove "${item.name}" from the list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final provider = context.read<GroceryProvider>();
      final messenger = ScaffoldMessenger.of(context);
      await provider.deleteGrocery(item.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('${item.name} deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => provider.restoreGrocery(item),
            ),
          ),
        );
    }
  }

  /// Quick-adds a one-off item straight to the shopping list via a dialog.
  static Future<void> quickAddToList(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    String category = 'Other';
    String unit = GroceryCategories.units.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add to shopping list'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Item name',
                    hintText: 'e.g. Paper plates',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*[.,]?\d*'),
                          ),
                        ],
                        decoration: const InputDecoration(labelText: 'Qty'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: GroceryCategories.units
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                        onChanged: (v) => setLocal(() => unit = v ?? unit),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: GroceryCategories.all
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setLocal(() => category = v ?? 'Other'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    final name = nameCtrl.text.trim();
    final quantity =
        double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 1;
    // Dispose controllers after the dialog's close animation completes, so the
    // dismissing TextField doesn't touch a disposed controller.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameCtrl.dispose();
      qtyCtrl.dispose();
    });
    if (confirmed != true || name.isEmpty || !context.mounted) return;

    final provider = context.read<GroceryProvider>();
    final who = context.read<AuthProvider>().resolvedDisplayName;
    await provider.quickAddToShoppingList(
      name,
      category: category,
      unit: unit,
      quantity: quantity <= 0 ? 1 : quantity,
      updatedBy: who,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('$name added to shopping list'),
          ),
        );
    }
  }
}
