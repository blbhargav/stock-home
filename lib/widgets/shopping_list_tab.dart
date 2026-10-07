import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/grocery_item.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../screens/home_actions.dart';
import '../theme/app_theme.dart';
import 'home_common.dart';

class ShoppingListTab extends StatelessWidget {
  const ShoppingListTab({super.key});

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

  static String _fmtQty(double qty) =>
      qty == qty.truncateToDouble() ? qty.toInt().toString() : qty.toString();

  Future<void> _markPurchased(
    BuildContext context,
    GroceryProvider provider,
    GroceryItem item,
  ) async {
    final name = context.read<AuthProvider>().resolvedDisplayName;
    final messenger = ScaffoldMessenger.of(context);
    final price = await _askPrice(context, item.name);
    // _askPrice returns a sentinel for cancel vs. a (possibly null) price.
    if (price == _priceCancelled) return;
    await provider.markInCart(item, updatedBy: name, price: price as double?);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${item.name} marked as purchased'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => provider.unmarkFromCart(item, updatedBy: name),
          ),
        ),
      );
  }

  /// Sentinel distinguishing "user cancelled" from "no price entered".
  static const Object _priceCancelled = Object();

  /// Prompts for an optional price. Returns the price (double), null if the
  /// user confirmed without a price, or [_priceCancelled] if dismissed.
  Future<Object?> _askPrice(BuildContext context, String itemName) async {
    final controller = TextEditingController();
    final result = await showDialog<Object?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark "$itemName" purchased'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add the price? (optional)'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
              ],
              decoration: const InputDecoration(
                prefixText: '₹ ',
                hintText: '0.00',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _priceCancelled),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim().replaceAll(',', '.');
              final value = double.tryParse(text);
              Navigator.pop(ctx, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<GroceryProvider>(
      builder: (context, provider, _) {
        final items = provider.shoppingList;
        if (items.isEmpty) {
          return FutureBuilder<List<LowStockSuggestion>>(
            future: provider.lowStockSuggestions(),
            builder: (context, snap) {
              final hasSuggestions = (snap.data ?? const []).isNotEmpty;
              if (!hasSuggestions) {
                return EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'Shopping list is empty',
                  message:
                      'Mark inventory items as "Needs purchase", or quick-add a '
                      'one-off item straight to the list.',
                  actionLabel: 'Quick add',
                  onAction: () => HomeActions.quickAddToList(context),
                );
              }
              return ListView(
                children: [
                  _SuggestionsSection(provider: provider),
                  const SizedBox(height: 24),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Your shopping list is empty.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        }

        final toBuy = items
            .where((i) => i.status == GroceryStatus.needsPurchase)
            .toList(growable: false);
        final inCart = items
            .where((i) => i.status == GroceryStatus.purchased)
            .toList(growable: false);
        final name = context.read<AuthProvider>().resolvedDisplayName;

        Widget divider() => Divider(
          height: 1,
          indent: 72,
          endIndent: 16,
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        );

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _ProgressSummary(total: items.length, done: inCart.length),
            ),
            SliverToBoxAdapter(child: _ShoppingSortBar(provider: provider)),
            SliverToBoxAdapter(child: _EstimatedTotal(provider: provider)),
            SliverToBoxAdapter(child: _SuggestionsSection(provider: provider)),
            if (toBuy.isNotEmpty) ...[
              _SectionHeader(label: 'To buy', count: toBuy.length),
              SliverList.separated(
                itemCount: toBuy.length,
                separatorBuilder: (_, _) => divider(),
                itemBuilder: (context, index) {
                  final item = toBuy[index];
                  final auth = context.read<AuthProvider>();
                  final myUid = auth.user?.uid;
                  return _SwipeToPurchaseTile(
                    key: ValueKey('swipe-${item.id}'),
                    item: item,
                    icon: _iconForCategory(item.category),
                    fmtQty: _fmtQty,
                    currentUid: myUid,
                    onTap: () => HomeActions.openDetail(context, item),
                    onMarkPurchased: () =>
                        _markPurchased(context, provider, item),
                    onIncrement: () => provider.setQuantity(
                      item,
                      item.quantity + 1,
                      updatedBy: name,
                    ),
                    onDecrement: () => provider.setQuantity(
                      item,
                      item.quantity - 1,
                      updatedBy: name,
                    ),
                    onToggleClaim: () {
                      if (item.claimedBy == myUid && item.isClaimed) {
                        provider.unclaimItem(item);
                      } else {
                        provider.claimItem(
                          item,
                          uid: myUid,
                          name: auth.resolvedDisplayName,
                        );
                      }
                    },
                  );
                },
              ),
            ],
            if (inCart.isNotEmpty) ...[
              _SectionHeader(
                label: 'In your cart',
                count: inCart.length,
                dimmed: true,
              ),
              SliverList.separated(
                itemCount: inCart.length,
                separatorBuilder: (_, _) => divider(),
                itemBuilder: (context, index) {
                  final item = inCart[index];
                  return _PurchasedTile(
                    key: ValueKey('done-${item.id}'),
                    item: item,
                    icon: _iconForCategory(item.category),
                    fmtQty: _fmtQty,
                    onTap: () => HomeActions.openDetail(context, item),
                    onUnmark: () =>
                        provider.unmarkFromCart(item, updatedBy: name),
                  );
                },
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      },
    );
  }
}

class _SuggestionsSection extends StatefulWidget {
  const _SuggestionsSection({required this.provider});

  final GroceryProvider provider;

  @override
  State<_SuggestionsSection> createState() => _SuggestionsSectionState();
}

class _SuggestionsSectionState extends State<_SuggestionsSection> {
  late Future<List<LowStockSuggestion>> _future;
  final Set<String> _added = {};

  @override
  void initState() {
    super.initState();
    _future = widget.provider.lowStockSuggestions();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder<List<LowStockSuggestion>>(
      future: _future,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const [];
        final suggestions = all.where((s) => !_added.contains(s.name)).toList();
        if (suggestions.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'SUGGESTED — RUNNING LOW?',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...suggestions.map(
                (s) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.reason,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _add(context, s),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _add(BuildContext context, LowStockSuggestion s) async {
    final name = context.read<AuthProvider>().resolvedDisplayName;
    setState(() => _added.add(s.name));
    await widget.provider.addSuggestionToList(s, updatedBy: name);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('${s.name} added to shopping list'),
          ),
        );
    }
  }
}

class _EstimatedTotal extends StatelessWidget {
  const _EstimatedTotal({required this.provider});

  final GroceryProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<({double total, int priced, int totalItems})?>(
      future: provider.estimateShoppingTotal(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || data.priced == 0) {
          return const SizedBox.shrink();
        }
        final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
        final approx = data.priced < data.totalItems;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.payments_outlined,
                  size: 18,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Estimated total: ${approx ? '~' : ''}${currency.format(data.total)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
                if (approx)
                  Text(
                    '${data.priced}/${data.totalItems} priced',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSecondaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShoppingSortBar extends StatelessWidget {
  const _ShoppingSortBar({required this.provider});

  final GroceryProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Icon(Icons.sort, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          PopupMenuButton<ShoppingSort>(
            initialValue: provider.shoppingSort,
            onSelected: provider.setShoppingSort,
            tooltip: 'Sort shopping list',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider.shoppingSort.label,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: scheme.primary),
              ],
            ),
            itemBuilder: (context) => ShoppingSort.values
                .map((s) => PopupMenuItem(value: s, child: Text(s.label)))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.total, required this.done});

  final int total;
  final int done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inStockColor = AppTheme.statusColor(GroceryStatus.inStock);
    final purchasedColor = AppTheme.statusColor(GroceryStatus.purchased);
    final progress = total == 0 ? 0.0 : done / total;
    final allDone = done == total;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: allDone
            ? inStockColor.withValues(alpha: 0.08)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allDone
              ? inStockColor.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allDone
                    ? Icons.check_circle_rounded
                    : Icons.shopping_cart_outlined,
                size: 18,
                color: allDone ? inStockColor : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                allDone
                    ? 'All done — great shop!'
                    : '$done of $total items purchased',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: allDone ? inStockColor : scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
              color: allDone ? inStockColor : purchasedColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    this.dimmed = false,
  });

  final String label;
  final int count;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppTheme.statusColor(GroceryStatus.needsPurchase);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Row(
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: dimmed ? scheme.onSurfaceVariant : scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: dimmed
                    ? scheme.outlineVariant.withValues(alpha: 0.3)
                    : accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: dimmed ? scheme.onSurfaceVariant : accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeToPurchaseTile extends StatelessWidget {
  const _SwipeToPurchaseTile({
    super.key,
    required this.item,
    required this.icon,
    required this.fmtQty,
    required this.onTap,
    required this.onMarkPurchased,
    required this.onToggleClaim,
    required this.currentUid,
    this.onIncrement,
    this.onDecrement,
  });

  final GroceryItem item;
  final IconData icon;
  final String Function(double) fmtQty;
  final VoidCallback onTap;
  final VoidCallback onMarkPurchased;
  final VoidCallback onToggleClaim;
  final String? currentUid;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    final green = AppTheme.statusColor(GroceryStatus.inStock);
    final claimedByMe = item.isClaimed && item.claimedBy == currentUid;

    return Dismissible(
      key: ValueKey('dismiss-${item.id}'),
      direction: DismissDirection.startToEnd,
      background: Container(
        color: green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              'Mark purchased',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        onMarkPurchased();
        return false;
      },
      child: _ShoppingTileContent(
        item: item,
        icon: icon,
        fmtQty: fmtQty,
        onTap: onTap,
        showSwipeHint: !item.isClaimed,
        onIncrement: onIncrement,
        onDecrement: onDecrement,
        onCheckTap: onMarkPurchased,
        claimBadge: item.isClaimed
            ? _ClaimBadge(
                label: claimedByMe
                    ? "You're getting this"
                    : '${item.claimedByName ?? 'Someone'} is getting this',
                mine: claimedByMe,
              )
            : null,
        trailing: _ClaimButton(
          claimedByMe: claimedByMe,
          claimed: item.isClaimed,
          onPressed: onToggleClaim,
        ),
      ),
    );
  }
}

class _PurchasedTile extends StatelessWidget {
  const _PurchasedTile({
    super.key,
    required this.item,
    required this.icon,
    required this.fmtQty,
    required this.onTap,
    required this.onUnmark,
  });

  final GroceryItem item;
  final IconData icon;
  final String Function(double) fmtQty;
  final VoidCallback onTap;
  final VoidCallback onUnmark;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: _ShoppingTileContent(
        item: item,
        icon: icon,
        fmtQty: fmtQty,
        onTap: onTap,
        strikethrough: true,
        trailing: IconButton(
          tooltip: 'Move back to list',
          icon: const Icon(Icons.undo_rounded, size: 20),
          onPressed: onUnmark,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final green = AppTheme.statusColor(GroceryStatus.inStock);
    return Tooltip(
      message: 'Mark purchased',
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: green, width: 2),
            color: green.withValues(alpha: 0.08),
          ),
          child: Icon(Icons.check, color: green),
        ),
      ),
    );
  }
}

class _MiniStepBtn extends StatelessWidget {
  const _MiniStepBtn({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
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

class _ShoppingTileContent extends StatelessWidget {
  const _ShoppingTileContent({
    required this.item,
    required this.icon,
    required this.fmtQty,
    required this.onTap,
    this.trailing,
    this.strikethrough = false,
    this.showSwipeHint = false,
    this.claimBadge,
    this.onIncrement,
    this.onDecrement,
    this.onCheckTap,
  });

  final GroceryItem item;
  final IconData icon;
  final String Function(double) fmtQty;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool strikethrough;
  final bool showSwipeHint;
  final Widget? claimBadge;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  /// When provided, the leading element becomes a tappable check-circle that
  /// marks the item purchased (used on the "to buy" list).
  final VoidCallback? onCheckTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final purchased = item.status == GroceryStatus.purchased;
    final iconColor = AppTheme.statusColor(
      purchased ? GroceryStatus.purchased : GroceryStatus.needsPurchase,
    );

    return Material(
      color: scheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              onCheckTap != null
                  ? _CheckCircle(onTap: onCheckTap!)
                  : Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 22, color: iconColor),
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              decoration: strikethrough
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showSwipeHint) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.swipe_right_outlined,
                            size: 14,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${fmtQty(item.quantity)} ${item.unit} · ${item.category}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              decoration: strikethrough
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (onIncrement != null || onDecrement != null) ...[
                          _MiniStepBtn(
                            icon: Icons.remove,
                            onPressed: item.quantity <= 1 ? null : onDecrement,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              fmtQty(item.quantity),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _MiniStepBtn(icon: Icons.add, onPressed: onIncrement),
                        ],
                      ],
                    ),
                    if (claimBadge != null) ...[
                      const SizedBox(height: 6),
                      claimBadge!,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _ClaimButton extends StatelessWidget {
  const _ClaimButton({
    required this.claimedByMe,
    required this.claimed,
    required this.onPressed,
  });

  final bool claimedByMe;
  final bool claimed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // If claimed by someone else, show a muted person icon (tap to still toggle
    // is allowed so a member can take over, but styled as informational).
    if (claimed && !claimedByMe) {
      return IconButton(
        tooltip: 'Someone is getting this',
        icon: Icon(Icons.person, color: scheme.primary),
        onPressed: onPressed,
      );
    }
    if (claimedByMe) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.check, size: 18),
        label: const Text('Got it'),
      );
    }
    return TextButton(onPressed: onPressed, child: const Text("I'll get it"));
  }
}

class _ClaimBadge extends StatelessWidget {
  const _ClaimBadge({required this.label, required this.mine});

  final String label;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = mine ? scheme.primary : scheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
