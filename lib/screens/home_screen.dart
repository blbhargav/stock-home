import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/grocery_categories.dart';
import '../models/grocery_item.dart';
import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../services/household_service.dart';
import '../services/product_lookup_service.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';
import '../widgets/account_sheet.dart';
import '../widgets/grocery_tile.dart';
import '../widgets/home_common.dart';
import '../widgets/inventory_widgets.dart';
import '../widgets/shopping_list_tab.dart';
import 'activity_feed_screen.dart';
import 'barcode_scanner_screen.dart';
import 'categories_tab.dart';
import 'home_actions.dart';
import 'insights_screen.dart';
import 'household_setup_screen.dart';
import 'members_screen.dart';
import 'recipe_import_screen.dart';

/// Main screen: grocery inventory with filters plus a shopping-list tab.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  void _openForm(BuildContext context, {GroceryItem? existing}) =>
      HomeActions.openForm(context, existing: existing);

  /// Quick-add a one-off item straight to the shopping list.
  Future<void> _quickAddToList(BuildContext context) =>
      HomeActions.quickAddToList(context);

  /// Scan a barcode while shopping: if the product matches a "to buy" item,
  /// mark it purchased; otherwise offer to add it to the list.
  Future<void> _scanToTickOff(BuildContext context) async {
    final provider = context.read<GroceryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final who = context.read<AuthProvider>().resolvedDisplayName;

    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (barcode == null || !context.mounted) return;

    final product = await ProductLookupService().lookup(barcode);
    if (!context.mounted) return;
    final scannedName = product?.name;
    if (scannedName == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Product not recognised. Add it manually.'),
        ),
      );
      return;
    }

    // Find a matching "to buy" item (case-insensitive contains either way).
    final toBuy = provider.shoppingList
        .where((i) => i.status == GroceryStatus.needsPurchase)
        .toList();
    GroceryItem? match;
    final lower = scannedName.toLowerCase();
    for (final i in toBuy) {
      final n = i.name.toLowerCase();
      if (n == lower || n.contains(lower) || lower.contains(n)) {
        match = i;
        break;
      }
    }

    if (match != null) {
      await provider.markInCart(match, updatedBy: who);
      if (context.mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('✓ ${match.name} marked purchased'),
            ),
          );
      }
    } else {
      // Not on the list — offer to add it.
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('"$scannedName" isn\'t on your list'),
          content: const Text('Add it to the shopping list?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (add == true) {
        await provider.quickAddToShoppingList(
          scannedName,
          category: product?.category,
          updatedBy: who,
        );
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('$scannedName added to shopping list'),
            ),
          );
        }
      }
    }
  }

  Future<void> _markAllPurchased(
    BuildContext context,
    GroceryProvider provider,
  ) async {
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
            IconButton(
              tooltip: 'Scan to tick off',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => _scanToTickOff(context),
            ),
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
          const OfflineBanner(),
          Expanded(
            child: _tabIndex == 0
                ? const _InventoryTab()
                : _tabIndex == 1
                ? const CategoriesTab()
                : const ShoppingListTab(),
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
      onManageMembers: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const MembersScreen())),
      onInsights: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const InsightsScreen())),
      onActivity: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ActivityFeedScreen())),
      onRecipeImport: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const RecipeImportScreen())),
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
  bool _listeningSearch = false;

  // Multi-select state.
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    if (_listeningSearch) SpeechService.instance.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleSearchDictation(GroceryProvider provider) async {
    if (_listeningSearch) {
      await SpeechService.instance.stop();
      if (mounted) setState(() => _listeningSearch = false);
      return;
    }
    setState(() => _listeningSearch = true);
    await SpeechService.instance.listen(
      onResult: (text) {
        if (!mounted) return;
        setState(() {
          _searchCtrl.text = text;
          _searchCtrl.selection = TextSelection.collapsed(
            offset: _searchCtrl.text.length,
          );
        });
        provider.setSearch(text);
      },
    );
    // When the engine stops on its own (silence), reflect that in the UI.
    if (mounted && !SpeechService.instance.isListening) {
      setState(() => _listeningSearch = false);
    }
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
                  IconButton(
                    tooltip: _listeningSearch
                        ? 'Stop listening'
                        : 'Search by voice',
                    icon: Icon(
                      _listeningSearch ? Icons.mic : Icons.mic_none,
                      color: _listeningSearch ? scheme.primary : null,
                    ),
                    onPressed: () => _toggleSearchDictation(provider),
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
            PantrySummaryStrip(provider: provider),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  InventoryFilterChip(
                    label: 'All',
                    filter: GroceryFilter.all,
                    selected: provider.filter == GroceryFilter.all,
                  ),
                  InventoryFilterChip(
                    label: 'In stock',
                    filter: GroceryFilter.inStock,
                    selected: provider.filter == GroceryFilter.inStock,
                  ),
                  InventoryFilterChip(
                    label: 'To buy',
                    count: provider.needsPurchaseCount,
                    countColor: AppTheme.statusColor(
                      GroceryStatus.needsPurchase,
                    ),
                    filter: GroceryFilter.needsPurchase,
                    selected: provider.filter == GroceryFilter.needsPurchase,
                  ),
                  InventoryFilterChip(
                    label: 'Expiring soon',
                    count: provider.expiringSoonCount,
                    countColor: AppTheme.statusColor(GroceryStatus.runningLow),
                    filter: GroceryFilter.expiringSoon,
                    selected: provider.filter == GroceryFilter.expiringSoon,
                  ),
                  InventoryFilterChip(
                    label: 'Expired',
                    count: provider.expiredCount,
                    countColor: AppTheme.statusColor(
                      GroceryStatus.needsPurchase,
                    ),
                    filter: GroceryFilter.expired,
                    selected: provider.filter == GroceryFilter.expired,
                  ),
                ],
              ),
            ),
            SortGroupBar(provider: provider),
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
        return EmptyState(
          icon: Icons.shopping_basket_outlined,
          title: 'No groceries yet',
          message:
              'Add your first item to start tracking your home stock together.',
          actionLabel: 'Add item',
          onAction: () => HomeActions.openForm(context),
        );
      }
      final query = provider.search;
      final isSearch = query.isNotEmpty;
      return EmptyState(
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

    final name = context.read<AuthProvider>().resolvedDisplayName;

    Widget buildTile(GroceryItem item) {
      final selected = _selectedIds.contains(item.id);
      final tile = GroceryTile(
        item: item,
        onTap: () {
          if (_selectionMode) {
            _toggleSelected(item.id);
          } else {
            HomeActions.openDetail(context, item);
          }
        },
        onEdit: () => HomeActions.openForm(context, existing: item),
        onMarkPurchased: () => provider.markPurchased(item, updatedBy: name),
        onMarkNeedsPurchase: () =>
            provider.markNeedsPurchase(item, updatedBy: name),
        onDelete: () => HomeActions.confirmDelete(context, item),
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
    BuildContext context,
    GroceryProvider provider,
  ) async {
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
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
    BuildContext context,
    GroceryProvider provider,
    String name,
  ) async {
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
    BuildContext context,
    GroceryProvider provider,
    String name,
  ) async {
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
              ListTile(title: Text(c), onTap: () => Navigator.pop(ctx, c)),
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
              Text(
                '$count selected',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
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
                icon: Icon(
                  Icons.delete_outline,
                  color: AppTheme.statusColor(GroceryStatus.needsPurchase),
                ),
                onPressed: count == 0 ? null : onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
