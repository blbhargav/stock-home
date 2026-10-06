import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/purchase_record.dart';
import '../providers/grocery_provider.dart';

/// A chronological feed of household purchases ("Sam bought Milk · 2h ago").
class ActivityFeedScreen extends StatelessWidget {
  const ActivityFeedScreen({super.key});

  static String _relativeTime(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 5) return '${weeks}w ago';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '${months}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: StreamBuilder<List<PurchaseRecord>>(
        stream: context.read<GroceryProvider>().watchPurchases(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final purchases = snapshot.data ?? const [];
          if (purchases.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 64, color: scheme.primary),
                    const SizedBox(height: 16),
                    Text('No activity yet',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'When household members buy items, their activity shows '
                      'up here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: purchases.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = purchases[index];
              final who = (p.purchasedBy == null || p.purchasedBy!.isEmpty)
                  ? 'Someone'
                  : p.purchasedBy!;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: const Icon(Icons.shopping_bag_outlined, size: 20),
                ),
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: who,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' bought '),
                      TextSpan(
                        text: p.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                subtitle: Text(p.category),
                trailing: Text(
                  _relativeTime(p.purchasedAt),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
