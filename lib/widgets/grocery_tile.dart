import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/grocery_item.dart';
import '../theme/app_theme.dart';

/// A card showing a grocery item with status, expiry and quick actions.
/// Used by both the inventory and shopping-list tabs.
class GroceryTile extends StatelessWidget {
  const GroceryTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onMarkPurchased,
    required this.onMarkNeedsPurchase,
    required this.onDelete,
    this.onEdit,
    this.onIncrement,
    this.onDecrement,
  });

  final GroceryItem item;
  final VoidCallback onTap;
  final VoidCallback onMarkPurchased;
  final VoidCallback onMarkNeedsPurchase;
  final VoidCallback onDelete;

  /// Called by the overflow "Edit" action. Falls back to [onTap] if null.
  final VoidCallback? onEdit;

  /// Optional quantity quick-adjust callbacks. When provided, +/- controls
  /// are shown on the tile.
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = AppTheme.statusColor(item.status);
    final (expiryLabel, expiryColor) = _expiryInfo(scheme);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              item.hasImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        item.imageUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        // Decode at ~thumbnail resolution (logical 44px at up to
                        // 3x DPI) instead of the full 1200px upload, saving
                        // memory and decode time for every row in the list.
                        cacheWidth: 132,
                        cacheHeight: 132,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            width: 44,
                            height: 44,
                            color: statusColor.withValues(alpha: 0.12),
                            child: const Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stack) => Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _categoryIcon(item.category),
                            size: 22,
                            color: statusColor,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _categoryIcon(item.category),
                        size: 22,
                        color: statusColor,
                      ),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_trimNum(item.quantity)} ${item.unit} · ${item.category}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(label: item.status.label, color: statusColor),
                        if (item.isStaple)
                          _Chip(
                            label: 'Staple',
                            color: scheme.primary,
                            icon: Icons.autorenew,
                          ),
                        if (expiryLabel.isNotEmpty)
                          _Chip(
                            label: expiryLabel,
                            color: expiryColor,
                            outlined: expiryColor == scheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                    if (item.hasNotes) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.sticky_note_2_outlined,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.notes!.trim(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (item.activityLabel != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.history,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.activityLabel!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (onIncrement != null || onDecrement != null) ...[
                      const SizedBox(height: 8),
                      _QuantityControls(
                        quantity: item.quantity,
                        unit: item.unit,
                        onIncrement: onIncrement,
                        onDecrement: onDecrement,
                      ),
                    ],
                  ],
                ),
              ),
              _OverflowMenu(
                item: item,
                onMarkPurchased: onMarkPurchased,
                onMarkNeedsPurchase: onMarkNeedsPurchase,
                onEdit: onEdit ?? onTap,
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Returns the expiry chip label and color for the current item.
  (String, Color) _expiryInfo(ColorScheme scheme) {
    final expiry = item.expiryDate;
    if (expiry == null) return ('', Colors.transparent);

    if (item.isExpired) {
      return (
        'Expired ${DateFormat('MMM d').format(expiry)}',
        AppTheme.statusColor(GroceryStatus.needsPurchase),
      );
    }
    if (item.expiresWithin(3)) {
      final days = item.daysUntilExpiry ?? 0;
      final label = days <= 0 ? 'Expires today' : 'Expires in ${days}d';
      return (label, AppTheme.statusColor(GroceryStatus.runningLow));
    }
    return (
      'Best by ${DateFormat.yMMMd().format(expiry)}',
      scheme.onSurfaceVariant,
    );
  }

  String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  IconData _categoryIcon(String category) {
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
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.item,
    required this.onMarkPurchased,
    required this.onMarkNeedsPurchase,
    required this.onEdit,
    required this.onDelete,
  });

  final GroceryItem item;
  final VoidCallback onMarkPurchased;
  final VoidCallback onMarkNeedsPurchase;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dangerColor = AppTheme.statusColor(GroceryStatus.needsPurchase);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      iconSize: 20,
      padding: EdgeInsets.zero,
      tooltip: 'More options',
      onSelected: (value) {
        switch (value) {
          case 'purchased':
            onMarkPurchased();
            break;
          case 'needs':
            onMarkNeedsPurchase();
            break;
          case 'edit':
            onEdit();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        if (item.status != GroceryStatus.inStock)
          const PopupMenuItem(
            value: 'purchased',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle_outline),
              title: Text('Mark purchased'),
              dense: true,
            ),
          ),
        if (item.status != GroceryStatus.needsPurchase)
          const PopupMenuItem(
            value: 'needs',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add_shopping_cart_outlined),
              title: Text('Add to shopping list'),
              dense: true,
            ),
          ),
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit'),
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: dangerColor),
            title: Text('Delete', style: TextStyle(color: dangerColor)),
            dense: true,
          ),
        ),
      ],
    );
  }
}

class _QuantityControls extends StatelessWidget {
  const _QuantityControls({
    required this.quantity,
    required this.unit,
    required this.onIncrement,
    required this.onDecrement,
  });

  final double quantity;
  final String unit;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundIconButton(
          icon: Icons.remove,
          tooltip: 'Decrease quantity',
          onPressed: quantity <= 0 ? null : onDecrement,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '${_trim(quantity)} $unit',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
        _RoundIconButton(
          icon: Icons.add,
          tooltip: 'Increase quantity',
          onPressed: onIncrement,
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 18,
        style: IconButton.styleFrom(
          backgroundColor: scheme.surfaceContainerHighest,
          shape: const CircleBorder(),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    this.outlined = false,
    this.icon,
  });

  final String label;
  final Color color;

  /// When true the chip uses a border + muted text instead of a color fill.
  final bool outlined;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = outlined ? scheme.onSurfaceVariant : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.13),
        border: Border.all(
          color: outlined
              ? scheme.outlineVariant
              : color.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
