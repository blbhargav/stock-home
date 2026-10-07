import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/grocery_item.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../theme/app_theme.dart';
import 'grocery_form_screen.dart';

/// Read-only view of a grocery item with all its details, photos and actions.
class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  /// We take the id and read the live item from the provider so the detail
  /// view updates in real time (and reflects edits immediately).
  final String itemId;

  static IconData _iconForCategory(String category) {
    switch (category) {
      case 'Fruits & Vegetables':
        return Icons.eco_outlined;
      case 'Dairy & Eggs':
        return Icons.egg_outlined;
      case 'Meat & Seafood':
        return Icons.set_meal_outlined;
      case 'Bakery':
        return Icons.bakery_dining_outlined;
      case 'Pantry & Dry Goods':
        return Icons.rice_bowl_outlined;
      case 'Frozen':
        return Icons.ac_unit;
      case 'Beverages':
        return Icons.local_drink_outlined;
      case 'Snacks':
        return Icons.cookie_outlined;
      case 'Household':
        return Icons.cleaning_services_outlined;
      default:
        return Icons.shopping_basket_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GroceryProvider>(
      builder: (context, provider, _) {
        GroceryItem? item;
        for (final i in provider.allItems) {
          if (i.id == itemId) {
            item = i;
            break;
          }
        }

        if (item == null) {
          // Item was deleted (possibly by another member) — close gracefully.
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text('This item is no longer available.'),
            ),
          );
        }

        return _DetailBody(item: item, provider: provider);
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.item, required this.provider});

  final GroceryItem item;
  final GroceryProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = AppTheme.statusColor(item.status);
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroceryFormScreen(existing: item),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Hero: label image or category icon ──────────────────────────
          if (item.hasImage)
            GestureDetector(
              onTap: () => _openFullscreen(context, item.imageUrl!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  item.imageUrl!,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : Container(
                          height: 220,
                          color: scheme.surfaceContainerHighest,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                  errorBuilder: (context, error, stack) =>
                      _iconHero(scheme, statusColor),
                ),
              ),
            )
          else
            _iconHero(scheme, statusColor),
          const SizedBox(height: 16),

          // ── Title + status chips ─────────────────────────────────────────
          Text(
            item.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, item.status.label, statusColor),
              if (item.isStaple)
                _chip(context, 'Staple', scheme.primary, icon: Icons.autorenew),
              if (item.isClaimed)
                _chip(
                  context,
                  '${item.claimedByName ?? 'Someone'} is getting this',
                  scheme.tertiary,
                  icon: Icons.shopping_bag_outlined,
                ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Info rows ────────────────────────────────────────────────────
          _InfoRow(
            icon: Icons.straighten_outlined,
            label: 'Quantity',
            value: '${_fmt(item.quantity)} ${item.unit}',
          ),
          _InfoRow(
            icon: Icons.category_outlined,
            label: 'Category',
            value: item.category,
          ),
          _InfoRow(
            icon: Icons.shopping_cart_outlined,
            label: 'Purchase date',
            value: item.purchaseDate == null
                ? 'Not set'
                : dateFormat.format(item.purchaseDate!),
          ),
          _InfoRow(
            icon: Icons.event_busy_outlined,
            label: 'Expiry date',
            value: item.expiryDate == null
                ? 'Not set'
                : dateFormat.format(item.expiryDate!),
            valueColor: item.isExpired
                ? AppTheme.statusColor(GroceryStatus.needsPurchase)
                : null,
          ),
          if (item.hasNotes)
            _InfoRow(
              icon: Icons.sticky_note_2_outlined,
              label: 'Notes',
              value: item.notes!,
            ),
          if (item.activityLabel != null)
            _InfoRow(
              icon: Icons.history,
              label: 'Last updated',
              value: item.activityLabel!,
            ),

          // ── User photos ──────────────────────────────────────────────────
          if (item.photos.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'PHOTOS',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: item.photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final url = item.photos[index];
                  return GestureDetector(
                    onTap: () => _openFullscreen(context, url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                        // Thumbnail-res decode (110 logical × 3x DPI).
                        cacheWidth: 330,
                        cacheHeight: 330,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : Container(
                                width: 110,
                                height: 110,
                                color: scheme.surfaceContainerHighest,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                        errorBuilder: (context, error, stack) => Container(
                          width: 110,
                          height: 110,
                          color: scheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),

      // ── Quick actions ──────────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _toggleShoppingList(context),
                  icon: Icon(
                    item.status == GroceryStatus.needsPurchase
                        ? Icons.remove_shopping_cart_outlined
                        : Icons.add_shopping_cart_outlined,
                  ),
                  label: Text(
                    item.status == GroceryStatus.needsPurchase
                        ? 'On the list'
                        : 'Add to list',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _markPurchased(context),
                  icon: const Icon(Icons.check),
                  label: const Text('Purchased'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconHero(ColorScheme scheme, Color statusColor) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        ItemDetailScreen._iconForCategory(item.category),
        size: 72,
        color: statusColor,
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    Color color, {
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _openFullscreen(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  void _markPurchased(BuildContext context) {
    final name = context.read<AuthProvider>().resolvedDisplayName;
    provider.markPurchased(item, updatedBy: name);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${item.name} marked as purchased'),
        ),
      );
  }

  void _toggleShoppingList(BuildContext context) {
    final name = context.read<AuthProvider>().resolvedDisplayName;
    if (item.status == GroceryStatus.needsPurchase) {
      provider.markPurchased(item, updatedBy: name);
    } else {
      provider.markNeedsPurchase(item, updatedBy: name);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('${item.name} added to shopping list'),
          ),
        );
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
