import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/grocery_item.dart';
import '../providers/grocery_provider.dart';
import '../screens/expiry_calendar_screen.dart';
import '../theme/app_theme.dart';

/// A row of tappable summary cards (expiring soon / to buy / expired) shown
/// above the inventory list. Hidden entirely when there's nothing to report.
class PantrySummaryStrip extends StatelessWidget {
  const PantrySummaryStrip({super.key, required this.provider});

  final GroceryProvider provider;

  @override
  Widget build(BuildContext context) {
    final toBuy = provider.needsPurchaseCount;
    final expiringSoon = provider.expiringSoonCount;
    final expired = provider.expiredCount;

    // Nothing to report — hide the strip entirely.
    if (toBuy == 0 && expiringSoon == 0 && expired == 0) {
      return const SizedBox.shrink();
    }

    final amber = AppTheme.statusColor(GroceryStatus.runningLow);
    final red = AppTheme.statusColor(GroceryStatus.needsPurchase);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          if (expiringSoon > 0)
            Expanded(
              child: _SummaryCard(
                count: expiringSoon,
                label: 'Expiring soon',
                icon: Icons.schedule,
                color: amber,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ExpiryCalendarScreen(),
                  ),
                ),
              ),
            ),
          if (expiringSoon > 0 && (toBuy > 0 || expired > 0))
            const SizedBox(width: 8),
          if (toBuy > 0)
            Expanded(
              child: _SummaryCard(
                count: toBuy,
                label: 'To buy',
                icon: Icons.shopping_cart_outlined,
                color: red,
                onTap: () => provider.setFilter(GroceryFilter.needsPurchase),
              ),
            ),
          if (toBuy > 0 && expired > 0) const SizedBox(width: 8),
          if (expired > 0)
            Expanded(
              child: _SummaryCard(
                count: expired,
                label: 'Expired',
                icon: Icons.error_outline,
                color: red,
                onTap: () => provider.setFilter(GroceryFilter.expired),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final int count;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sort selector + group-by-category toggle shown above the inventory list.
class SortGroupBar extends StatelessWidget {
  const SortGroupBar({super.key, required this.provider});

  final GroceryProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Icon(Icons.sort, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          PopupMenuButton<GrocerySort>(
            initialValue: provider.sort,
            onSelected: provider.setSort,
            tooltip: 'Sort by',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider.sort.label,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: scheme.primary),
              ],
            ),
            itemBuilder: (context) => GrocerySort.values
                .map((s) => PopupMenuItem(value: s, child: Text(s.label)))
                .toList(),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Group'),
              Switch(
                value: provider.groupByCategory,
                onChanged: provider.setGroupByCategory,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A filter chip with an optional count badge, used in the inventory filter row.
class InventoryFilterChip extends StatelessWidget {
  const InventoryFilterChip({
    super.key,
    required this.label,
    required this.filter,
    required this.selected,
    this.count,
    this.countColor,
  });

  final String label;
  final GroceryFilter filter;
  final bool selected;
  final int? count;
  final Color? countColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.onSecondaryContainer.withValues(alpha: 0.20)
                      : (countColor ?? scheme.primary).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? scheme.onSecondaryContainer
                        : (countColor ?? scheme.primary),
                  ),
                ),
              ),
            ],
          ],
        ),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => context.read<GroceryProvider>().setFilter(filter),
      ),
    );
  }
}
