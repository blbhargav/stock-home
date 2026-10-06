import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/grocery_categories.dart';
import '../models/grocery_item.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../services/household_service.dart';
import '../theme/app_theme.dart';
import '../widgets/account_sheet.dart';
import '../widgets/grocery_tile.dart';
import 'activity_feed_screen.dart';
import 'categories_tab.dart';
import 'grocery_form_screen.dart';
import 'insights_screen.dart';
import 'item_detail_screen.dart';
import 'household_setup_screen.dart';
import 'members_screen.dart';

/// Main screen: grocery inventory with filters plus a shopping-list tab.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  void _openForm(BuildContext context, {GroceryItem? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroceryFormScreen(existing: existing),
      ),
    );
  }

  void _openDetail(BuildContext context, GroceryItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(itemId: item.id),
      ),
    );
  }

  /// Quick-add a one-off item straight to the shopping list.
  Future<void> _quickAddToList(BuildContext context) async {
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
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*[.,]?\d*')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Qty',
                        ),
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
                            .map((u) =>
                                DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) =>
                            setLocal(() => unit = v ?? unit),
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
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
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

  Future<void> _confirmDelete(
      BuildContext context, GroceryItem item) async {
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

  Future<void> _markAllPurchased(
      BuildContext context, GroceryProvider provider) async {
    final count = provider.needsPurchaseCount;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark all as purchased?'),
        content: Text(
          'This will mark all $count remaining items as purchased.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark all'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await provider.markAllInCart(
        updatedBy: context.read<AuthProvider>().resolvedDisplayName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tabIndex == 0
              ? 'StockHome'
              : _tabIndex == 1
                  ? 'Categories'
                  : 'Shopping List',
        ),
        actions: [
          if (_tabIndex == 2)
            Consumer<GroceryProvider>(
              builder: (context, provider, _) {
                if (provider.needsPurchaseCount == 0) {
                  return const SizedBox.shrink();
                }
                return TextButton(
                  onPressed: () => _markAllPurchased(context, provider),
                  child: const Text('Mark all'),
                );
              },
            ),
          IconButton(
            tooltip: 'Household & account',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => _showAccountSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          const _OfflineBanner(),
          Expanded(
            child: _tabIndex == 0
                ? const _InventoryTab()
                : _tabIndex == 1
                    ? const CategoriesTab()
                    : const _ShoppingListTab(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabIndex == 2) {
            _quickAddToList(context);
          } else {
            _openForm(context);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabIndex == 2 ? 'Quick add' : 'Add'),
      ),
      bottomNavigationBar: Consumer<GroceryProvider>(
        builder: (context, provider, _) {
          return NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (i) => setState(() => _tabIndex = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: 'Inventory',
              ),
              const NavigationDestination(
                icon: Icon(Icons.category_outlined),
                selectedIcon: Icon(Icons.category),
                label: 'Categories',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: provider.needsPurchaseCount > 0,
                  label: Text('${provider.needsPurchaseCount}'),
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
                selectedIcon: const Icon(Icons.shopping_cart),
                label: 'Shopping',
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAccountSheet(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Grab current household name + member count (one-shot).
    HouseholdInfo? household;
    try {
      household = await auth.watchHousehold().first;
    } catch (_) {
      household = null;
    }
    if (!context.mounted) return;

    final info = AccountInfo(
      displayName: auth.resolvedDisplayName,
      email: auth.user?.email ?? '',
      householdName: household?.name ?? 'Your household',
      householdCode: auth.householdId ?? '—',
      memberCount: household?.memberCount ?? 1,
    );

    await showAccountSheet(
      context,
      info: info,
      onSwitchHousehold: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const HouseholdSetupScreen(addingAnother: true),
        ),
      ),
      onSignOut: () => auth.signOut(),
      onRemindersChanged: () =>
          context.read<GroceryProvider>().refreshReminders(),
      onManageMembers: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MembersScreen()),
      ),
      onInsights: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const InsightsScreen()),
      ),
      onActivity: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ActivityFeedScreen()),
      ),
    );

    // Keep the messenger reference used to avoid using context after await.
    messenger.hideCurrentSnackBar();
  }
}

class _InventoryTab extends StatefulWidget {
  const _InventoryTab();

  @override
  State<_InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<_InventoryTab> {
  final _searchCtrl = TextEditingController();

  // Multi-select state.
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<GroceryProvider>(
      builder: (context, provider, _) {
        if (provider.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                controller: _searchCtrl,
                hintText: 'Search groceries…',
                leading: Icon(Icons.search, color: scheme.onSurfaceVariant),
                trailing: [
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchCtrl.clear();
                        provider.setSearch('');
                        setState(() {});
                      },
                    ),
                ],
                onChanged: (value) {
                  provider.setSearch(value);
                  setState(() {});
                },
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                  scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
              ),
            ),
            _PantrySummaryStrip(provider: provider),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChip(
                    label: 'All',
                    filter: GroceryFilter.all,
                    selected: provider.filter == GroceryFilter.all,
                  ),
                  _FilterChip(
                    label: 'In stock',
                    filter: GroceryFilter.inStock,
                    selected: provider.filter == GroceryFilter.inStock,
                  ),
                  _FilterChip(
                    label: 'To buy',
                    count: provider.needsPurchaseCount,
                    countColor: AppTheme.statusColor(GroceryStatus.needsPurchase),
                    filter: GroceryFilter.needsPurchase,
                    selected: provider.filter == GroceryFilter.needsPurchase,
                  ),
                  _FilterChip(
                    label: 'Expiring soon',
                    count: provider.expiringSoonCount,
                    countColor: AppTheme.statusColor(GroceryStatus.runningLow),
                    filter: GroceryFilter.expiringSoon,
                    selected: provider.filter == GroceryFilter.expiringSoon,
                  ),
                  _FilterChip(
                    label: 'Expired',
                    count: provider.expiredCount,
                    countColor: AppTheme.statusColor(GroceryStatus.needsPurchase),
                    filter: GroceryFilter.expired,
                    selected: provider.filter == GroceryFilter.expired,
                  ),
                ],
              ),
            ),
            _SortGroupBar(provider: provider),
            const SizedBox(height: 4),
            Expanded(child: _buildList(context, provider)),
          ],
        );
      },
    );
  }

  Widget _buildList(BuildContext context, GroceryProvider provider) {
    final items = provider.visibleItems;
    if (items.isEmpty) {
      if (provider.allItems.isEmpty) {
        final home = context.findAncestorStateOfType<_HomeScreenState>()!;
        return _EmptyState(
          icon: Icons.shopping_basket_outlined,
          title: 'No groceries yet',
          message:
              'Add your first item to start tracking your home stock together.',
          actionLabel: 'Add item',
          onAction: () => home._openForm(context),
        );
      }
      final query = provider.search;
      final isSearch = query.isNotEmpty;
      return _EmptyState(
        icon: isSearch ? Icons.search_off : Icons.filter_list_off,
        title: isSearch ? 'No results for "$query"' : 'Nothing here',
        message: isSearch
            ? 'Try a different name or category.'
            : 'No items match the selected filter.',
        actionLabel: 'Clear filter',
        onAction: () {
          _searchCtrl.clear();
          provider.setSearch('');
          provider.setFilter(GroceryFilter.all);
          setState(() {});
        },
      );
    }

    final home = context.findAncestorStateOfType<_HomeScreenState>()!;
    final name = context.read<AuthProvider>().resolvedDisplayName;

    Widget buildTile(GroceryItem item) {
      final selected = _selectedIds.contains(item.id);
      final tile = GroceryTile(
        item: item,
        onTap: () {
          if (_selectionMode) {
            _toggleSelected(item.id);
          } else {
            home._openDetail(context, item);
          }
        },
        onEdit: () => home._openForm(context, existing: item),
        onMarkPurchased: () => provider.markPurchased(item, updatedBy: name),
        onMarkNeedsPurchase: () =>
            provider.markNeedsPurchase(item, updatedBy: name),
        onDelete: () => home._confirmDelete(context, item),
        onIncrement: () => provider.adjustQuantity(item, 1, updatedBy: name),
        onDecrement: () => provider.adjustQuantity(item, -1, updatedBy: name),
      );

      final scheme = Theme.of(context).colorScheme;
      return GestureDetector(
        onLongPress: _selectionMode ? null : () => _enterSelection(item.id),
        child: Stack(
          children: [
            // Dim/absorb tile's own gestures when selecting so tap toggles.
            if (_selectionMode)
              IgnorePointer(
                child: Opacity(opacity: selected ? 1 : 0.85, child: tile),
              )
            else
              tile,
            if (_selectionMode)
              Positioned.fill(
                child: Material(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.10)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => _toggleSelected(item.id),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: selected
                              ? scheme.primary
                              : scheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    Widget list;
    if (provider.groupByCategory) {
      final groups = provider.groupedVisibleItems;
      final categories = groups.keys.toList();
      list = ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final groupItems = groups[category]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
                child: Text(
                  '${category.toUpperCase()}  ·  ${groupItems.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              ...groupItems.map(buildTile),
            ],
          );
        },
      );
    } else {
      list = ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        itemCount: items.length,
        itemBuilder: (context, index) => buildTile(items[index]),
      );
    }

    if (!_selectionMode) return list;

    // Selection action bar at the bottom.
    return Column(
      children: [
        Expanded(child: list),
        _SelectionActionBar(
          count: _selectedIds.length,
          onCancel: _exitSelection,
          onDelete: () => _bulkDelete(context, provider),
          onAddToList: () => _bulkAddToList(context, provider, name),
          onChangeCategory: () => _bulkChangeCategory(context, provider, name),
        ),
      ],
    );
  }

  List<GroceryItem> _selectedItems(GroceryProvider provider) => provider
      .allItems
      .where((i) => _selectedIds.contains(i.id))
      .toList(growable: false);

  Future<void> _bulkDelete(
      BuildContext context, GroceryProvider provider) async {
    final selected = _selectedItems(provider);
    if (selected.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${selected.length} items?'),
        content: const Text('This removes them from the household list.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await provider.deleteItems(selected);
    _exitSelection();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${deleted.length} items deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => provider.restoreItems(deleted),
          ),
        ),
      );
  }

  Future<void> _bulkAddToList(
      BuildContext context, GroceryProvider provider, String name) async {
    final selected = _selectedItems(provider);
    if (selected.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await provider.addItemsToShoppingList(selected, updatedBy: name);
    _exitSelection();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${selected.length} items added to shopping list'),
        ),
      );
  }

  Future<void> _bulkChangeCategory(
      BuildContext context, GroceryProvider provider, String name) async {
    final selected = _selectedItems(provider);
    if (selected.isEmpty) return;
    final category = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in GroceryCategories.all)
              ListTile(
                title: Text(c),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (category == null) return;
    await provider.changeCategory(selected, category, updatedBy: name);
    _exitSelection();
  }
}

class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.count,
    required this.onCancel,
    required this.onDelete,
    required this.onAddToList,
    required this.onChangeCategory,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onAddToList;
  final VoidCallback onChangeCategory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                onPressed: onCancel,
              ),
              Text('$count selected',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                tooltip: 'Add to shopping list',
                icon: const Icon(Icons.add_shopping_cart_outlined),
                onPressed: count == 0 ? null : onAddToList,
              ),
              IconButton(
                tooltip: 'Change category',
                icon: const Icon(Icons.category_outlined),
                onPressed: count == 0 ? null : onChangeCategory,
              ),
              IconButton(
                tooltip: 'Delete',
                icon: Icon(Icons.delete_outline,
                    color: AppTheme.statusColor(GroceryStatus.needsPurchase)),
                onPressed: count == 0 ? null : onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShoppingListTab extends StatelessWidget {
  const _ShoppingListTab();

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

  Future<void> _markPurchased(BuildContext context, GroceryProvider provider,
      GroceryItem item) async {
    final name = context.read<AuthProvider>().resolvedDisplayName;
    final messenger = ScaffoldMessenger.of(context);
    final price = await _askPrice(context, item.name);
    // _askPrice returns a sentinel for cancel vs. a (possibly null) price.
    if (price == _priceCancelled) return;
    await provider.markInCart(item,
        updatedBy: name, price: price as double?);
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
          final home = context.findAncestorStateOfType<_HomeScreenState>()!;
          return FutureBuilder<List<LowStockSuggestion>>(
            future: provider.lowStockSuggestions(),
            builder: (context, snap) {
              final hasSuggestions = (snap.data ?? const []).isNotEmpty;
              if (!hasSuggestions) {
                return _EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'Shopping list is empty',
                  message:
                      'Mark inventory items as "Needs purchase", or quick-add a '
                      'one-off item straight to the list.',
                  actionLabel: 'Quick add',
                  onAction: () => home._quickAddToList(context),
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
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
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
        final home = context.findAncestorStateOfType<_HomeScreenState>()!;
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
              child: _ProgressSummary(
                total: items.length,
                done: inCart.length,
              ),
            ),
            SliverToBoxAdapter(
              child: _ShoppingSortBar(provider: provider),
            ),
            SliverToBoxAdapter(
              child: _EstimatedTotal(provider: provider),
            ),
            SliverToBoxAdapter(
              child: _SuggestionsSection(provider: provider),
            ),
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
                    onTap: () => home._openDetail(context, item),
                    onMarkPurchased: () =>
                        _markPurchased(context, provider, item),
                    onIncrement: () => provider.setQuantity(
                        item, item.quantity + 1,
                        updatedBy: name),
                    onDecrement: () => provider.setQuantity(
                        item, item.quantity - 1,
                        updatedBy: name),
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
                  label: 'In your cart', count: inCart.length, dimmed: true),
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
                    onTap: () => home._openDetail(context, item),
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
        final suggestions =
            all.where((s) => !_added.contains(s.name)).toList();
        if (suggestions.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 16, color: scheme.primary),
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
              ...suggestions.map((s) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                s.reason,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant),
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
                  )),
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
        final currency =
            NumberFormat.currency(symbol: '₹', decimalDigits: 0);
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
                Icon(Icons.payments_outlined,
                    size: 18, color: scheme.onSecondaryContainer),
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
                          color: scheme.onSecondaryContainer
                              .withValues(alpha: 0.8),
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
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Text(
              'Mark purchased',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
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
        purchased ? GroceryStatus.purchased : GroceryStatus.needsPurchase);

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
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.5),
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
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              fmtQty(item.quantity),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          _MiniStepBtn(
                            icon: Icons.add,
                            onPressed: onIncrement,
                          ),
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
    return TextButton(
      onPressed: onPressed,
      child: const Text("I'll get it"),
    );
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

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Consumer<GroceryProvider>(
      builder: (context, provider, _) {
        final offline = provider.isOffline;
        final pending = provider.hasPendingWrites;
        if (!offline && !pending) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;
        final runningLow = AppTheme.statusColor(GroceryStatus.runningLow);
        final (icon, message, color) = offline
            ? (
                Icons.cloud_off_outlined,
                'Offline — changes will sync when you reconnect',
                runningLow,
              )
            : (
                Icons.sync,
                'Syncing changes…',
                scheme.primary,
              );

        return Material(
          color: color.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
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

class _PantrySummaryStrip extends StatelessWidget {
  const _PantrySummaryStrip({required this.provider});

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
                onTap: () => provider.setFilter(GroceryFilter.expiringSoon),
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

class _SortGroupBar extends StatelessWidget {
  const _SortGroupBar({required this.provider});

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
                .map((s) =>
                    PopupMenuItem(value: s, child: Text(s.label)))
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
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
              child: Icon(icon, size: 36, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
