import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/grocery_categories.dart';
import '../models/grocery_item.dart';
import '../providers/grocery_provider.dart';
import '../theme/app_theme.dart';
import 'category_items_screen.dart';

/// Grid of all grocery categories showing item counts.
/// Tapping a card opens [CategoryItemsScreen] for that category.
class CategoriesTab extends StatelessWidget {
  const CategoriesTab({super.key});

  static const _categories = GroceryCategories.all;

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
        if (provider.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = provider.allItems;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final category = _categories[index];
            final icon = _iconForCategory(category);
            final categoryItems = items
                .where((i) => i.category == category)
                .toList();
            final total = categoryItems.length;
            final needsPurchase = categoryItems
                .where((i) => i.status == GroceryStatus.needsPurchase)
                .length;
            final expiringSoon = categoryItems
                .where((i) => !i.isExpired && i.expiresWithin(3))
                .length;
            final expired = categoryItems.where((i) => i.isExpired).length;

            return _CategoryCard(
              category: category,
              icon: icon,
              total: total,
              needsPurchase: needsPurchase,
              expiringSoon: expiringSoon,
              expired: expired,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CategoryItemsScreen(category: category, icon: icon),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.icon,
    required this.total,
    required this.needsPurchase,
    required this.expiringSoon,
    required this.expired,
    required this.onTap,
  });

  final String category;
  final IconData icon;
  final int total;
  final int needsPurchase;
  final int expiringSoon;
  final int expired;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primaryColor = AppTheme.statusColor(GroceryStatus.inStock);

    // Alert color: red if expired, amber if expiring soon, red if needs purchase.
    // Priority: expired > needs purchase > expiring soon.
    final Color? alertColor = expired > 0
        ? AppTheme.statusColor(GroceryStatus.needsPurchase)
        : needsPurchase > 0
        ? AppTheme.statusColor(GroceryStatus.needsPurchase)
        : expiringSoon > 0
        ? AppTheme.statusColor(GroceryStatus.runningLow)
        : null;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: alertColor != null
              ? alertColor.withValues(alpha: 0.4)
              : scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 22, color: primaryColor),
                  ),
                  const Spacer(),
                  // Item count badge (always visible).
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: total == 0
                              ? scheme.surfaceContainerHighest
                              : primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: total == 0
                                ? scheme.outlineVariant
                                : primaryColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          '$total',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: total == 0
                                ? scheme.onSurfaceVariant
                                : primaryColor,
                          ),
                        ),
                      ),
                      // Alert badge below count if needed.
                      if (alertColor != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: alertColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: alertColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            _alertLabel(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: alertColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text(
                category,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _alertLabel() {
    if (expired > 0) return '$expired expired';
    if (needsPurchase > 0) return '$needsPurchase to buy';
    if (expiringSoon > 0) return '$expiringSoon expiring';
    return '';
  }
}
