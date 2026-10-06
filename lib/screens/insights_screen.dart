import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/grocery_item.dart';
import '../models/purchase_record.dart';
import '../providers/grocery_provider.dart';
import '../theme/app_theme.dart';

/// Shows simple spend insights derived from the household's purchase history.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Spending & insights')),
      body: StreamBuilder<List<PurchaseRecord>>(
        stream: context.read<GroceryProvider>().watchPurchases(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final purchases = snapshot.data ?? const [];
          if (purchases.isEmpty) {
            return _empty(context);
          }

          final now = DateTime.now();
          final monthStart = DateTime(now.year, now.month);
          final thisMonth = purchases
              .where(
                (p) =>
                    p.purchasedAt != null &&
                    !p.purchasedAt!.isBefore(monthStart),
              )
              .toList();

          final monthSpend = thisMonth.fold<double>(
            0,
            (sum, p) => sum + (p.price ?? 0),
          );
          final totalSpend = purchases.fold<double>(
            0,
            (sum, p) => sum + (p.price ?? 0),
          );

          // Most-bought items (by count).
          final counts = <String, int>{};
          for (final p in purchases) {
            counts[p.name] = (counts[p.name] ?? 0) + 1;
          }
          final topItems = counts.keys.toList()
            ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

          final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'This month',
                      value: currency.format(monthSpend),
                      sub: '${thisMonth.length} purchases',
                      color: AppTheme.statusColor(GroceryStatus.inStock),
                      icon: Icons.calendar_month_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'All time',
                      value: currency.format(totalSpend),
                      sub: '${purchases.length} purchases',
                      color: AppTheme.statusColor(GroceryStatus.purchased),
                      icon: Icons.receipt_long_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Spend totals only count purchases where a price was entered.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'MOST BOUGHT',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...topItems.take(10).map((name) {
                final count = counts[name]!;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: Text('$count'),
                  ),
                  title: Text(name),
                  subtitle: Text(
                    count == 1 ? 'Bought once' : 'Bought $count times',
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'No purchases yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mark items as purchased (and optionally add a price) to see '
              'spending and your most-bought items here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String sub;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(sub, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
