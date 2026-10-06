import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/grocery_item.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../widgets/grocery_tile.dart';
import 'grocery_form_screen.dart';
import 'item_detail_screen.dart';

/// Shows all groceries in a specific [category], with the same tile/actions
/// as the inventory tab.
class CategoryItemsScreen extends StatelessWidget {
  const CategoryItemsScreen({
    super.key,
    required this.category,
    required this.icon,
  });

  final String category;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(category),
        leading: const BackButton(),
      ),
      body: Consumer<GroceryProvider>(
        builder: (context, provider, _) {
          final items = provider.allItems
              .where((i) => i.category == category)
              .toList(growable: false);

          if (items.isEmpty) {
            return _EmptyCategory(category: category);
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final name =
                  context.read<AuthProvider>().resolvedDisplayName;
              return GroceryTile(
                item: item,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ItemDetailScreen(itemId: item.id),
                  ),
                ),
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroceryFormScreen(existing: item),
                  ),
                ),
                onMarkPurchased: () =>
                    provider.markPurchased(item, updatedBy: name),
                onMarkNeedsPurchase: () =>
                    provider.markNeedsPurchase(item, updatedBy: name),
                onDelete: () => _confirmDelete(context, provider, item),
                onIncrement: () =>
                    provider.adjustQuantity(item, 1, updatedBy: name),
                onDecrement: () =>
                    provider.adjustQuantity(item, -1, updatedBy: name),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroceryFormScreen(),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    GroceryProvider provider,
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
}

class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.category_outlined,
                  size: 36, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'No items in $category',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add" to add your first item in this category.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
