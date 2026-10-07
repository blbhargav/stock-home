import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/grocery_item.dart';
import '../models/purchase_record.dart';
import '../models/recipe_parser.dart';
import '../services/export_service.dart';
import '../services/grocery_service.dart';
import '../services/notification_service.dart';
import '../services/purchase_service.dart';
import '../services/settings_service.dart';

/// Filter options for the grocery list.
enum GroceryFilter { all, inStock, needsPurchase, expiringSoon, expired }

/// Sort options for the inventory list.
enum GrocerySort { name, expiry, category, recentlyUpdated }

extension GrocerySortX on GrocerySort {
  String get label {
    switch (this) {
      case GrocerySort.name:
        return 'Name';
      case GrocerySort.expiry:
        return 'Expiry date';
      case GrocerySort.category:
        return 'Category';
      case GrocerySort.recentlyUpdated:
        return 'Recently updated';
    }
  }
}

/// Sort options for the shopping list.
enum ShoppingSort { name, category, recentlyAdded }

extension ShoppingSortX on ShoppingSort {
  String get label {
    switch (this) {
      case ShoppingSort.name:
        return 'Name';
      case ShoppingSort.category:
        return 'Category';
      case ShoppingSort.recentlyAdded:
        return 'Recently added';
    }
  }
}

/// A predicted "running low" item based on purchase regularity.
class LowStockSuggestion {
  const LowStockSuggestion({
    required this.name,
    required this.avgIntervalDays,
    required this.daysSinceLast,
    required this.overdueBy,
  });

  final String name;
  final int avgIntervalDays;
  final int daysSinceLast;
  final int overdueBy;

  /// A short human explanation, e.g. "Usually every 7 days · last bought 10d ago".
  String get reason {
    final every = avgIntervalDays == 1 ? 'day' : '$avgIntervalDays days';
    return 'Usually every $every · last bought ${daysSinceLast}d ago';
  }
}

/// Streams and mutates the grocery list for the active household.
class GroceryProvider extends ChangeNotifier {
  GroceryProvider({
    GroceryService? service,
    NotificationService? notifications,
    SettingsService? settings,
    PurchaseService? purchases,
  }) : _service = service ?? GroceryService(),
       _notifications = notifications ?? NotificationService.instance,
       _settings = settings ?? SettingsService(),
       _purchases = purchases ?? PurchaseService() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final sortIndex = await _settings.getSortIndex();
      final group = await _settings.getGroupByCategory();
      final shoppingSortIndex = await _settings.getShoppingSortIndex();
      _sort =
          GrocerySort.values[sortIndex.clamp(0, GrocerySort.values.length - 1)];
      _groupByCategory = group;
      _shoppingSort = ShoppingSort
          .values[shoppingSortIndex.clamp(0, ShoppingSort.values.length - 1)];
      notifyListeners();
    } catch (_) {
      // Ignore; defaults are fine.
    }
  }

  final GroceryService _service;
  final NotificationService _notifications;
  final SettingsService _settings;
  final PurchaseService _purchases;

  String? _householdId;
  StreamSubscription<GrocerySnapshot>? _sub;

  List<GroceryItem> _items = [];
  bool _loading = false;
  bool _isOffline = false;
  bool _hasPendingWrites = false;
  GroceryFilter _filter = GroceryFilter.all;
  GrocerySort _sort = GrocerySort.name;
  bool _groupByCategory = false;
  ShoppingSort _shoppingSort = ShoppingSort.name;
  String _search = '';

  // --- Cached view of the filtered+sorted inventory. ---
  // visibleItems is read several times per rebuild (and again indirectly by
  // groupedVisibleItems), each time filtering, copying and sorting the whole
  // list. We memoize the result and only recompute when an input changes.
  List<GroceryItem>? _visibleCache;
  Map<String, List<GroceryItem>>? _groupedCache;

  /// Discards the memoized visible/grouped lists so they recompute on next read.
  void _invalidateViewCache() {
    _visibleCache = null;
    _groupedCache = null;
  }

  List<GroceryItem> get allItems => List.unmodifiable(_items);

  /// Returns distinct, non-empty notes from all current items, ordered by
  /// frequency (most used first). Useful for note suggestions.
  List<String> get recentNotes {
    final counts = <String, int>{};
    for (final item in _items) {
      final note = item.notes?.trim();
      if (note == null || note.isEmpty) continue;
      counts[note] = (counts[note] ?? 0) + 1;
    }
    final sorted = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return sorted;
  }

  bool get loading => _loading;

  /// True when data is being served from the local cache (offline).
  bool get isOffline => _isOffline;

  /// True when local changes are waiting to sync to the server.
  bool get hasPendingWrites => _hasPendingWrites;

  GroceryFilter get filter => _filter;
  GrocerySort get sort => _sort;
  ShoppingSort get shoppingSort => _shoppingSort;
  bool get groupByCategory => _groupByCategory;
  String get search => _search;

  /// Number of items that need to be purchased.
  int get needsPurchaseCount =>
      _items.where((i) => i.status == GroceryStatus.needsPurchase).length;

  /// Number of items expiring within 3 days (and not yet expired).
  int get expiringSoonCount => _items.where((i) => i.expiresWithin(3)).length;

  /// Number of already expired items.
  int get expiredCount => _items.where((i) => i.isExpired).length;

  /// Items after applying the active filter and search query, sorted.
  /// Memoized; recomputed only when items/filter/search/sort change.
  List<GroceryItem> get visibleItems {
    final cached = _visibleCache;
    if (cached != null) return cached;

    Iterable<GroceryItem> result = _items;

    switch (_filter) {
      case GroceryFilter.all:
        break;
      case GroceryFilter.inStock:
        result = result.where(
          (i) =>
              i.status == GroceryStatus.inStock ||
              i.status == GroceryStatus.runningLow,
        );
        break;
      case GroceryFilter.needsPurchase:
        result = result.where((i) => i.status == GroceryStatus.needsPurchase);
        break;
      case GroceryFilter.expiringSoon:
        result = result.where((i) => i.expiresWithin(3));
        break;
      case GroceryFilter.expired:
        result = result.where((i) => i.isExpired);
        break;
    }

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      result = result.where(
        (i) =>
            i.name.toLowerCase().contains(q) ||
            i.category.toLowerCase().contains(q),
      );
    }

    final list = result.toList();
    _applySort(list);
    final out = List<GroceryItem>.unmodifiable(list);
    _visibleCache = out;
    return out;
  }

  void _applySort(List<GroceryItem> list) {
    switch (_sort) {
      case GrocerySort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case GrocerySort.expiry:
        // Items without an expiry date sort to the end.
        list.sort((a, b) {
          final ax = a.expiryDate;
          final bx = b.expiryDate;
          if (ax == null && bx == null) return 0;
          if (ax == null) return 1;
          if (bx == null) return -1;
          return ax.compareTo(bx);
        });
        break;
      case GrocerySort.category:
        list.sort((a, b) {
          final c = a.category.compareTo(b.category);
          return c != 0
              ? c
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
      case GrocerySort.recentlyUpdated:
        list.sort((a, b) {
          final ax = a.updatedAt;
          final bx = b.updatedAt;
          if (ax == null && bx == null) return 0;
          if (ax == null) return 1;
          if (bx == null) return -1;
          return bx.compareTo(ax); // most recent first
        });
        break;
    }
  }

  /// Visible items grouped by category (sorted category names), for the
  /// grouped inventory view.
  Map<String, List<GroceryItem>> get groupedVisibleItems {
    final cached = _groupedCache;
    if (cached != null) return cached;
    final groups = <String, List<GroceryItem>>{};
    for (final item in visibleItems) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    final sortedKeys = groups.keys.toList()..sort();
    final out = {for (final k in sortedKeys) k: groups[k]!};
    _groupedCache = out;
    return out;
  }

  /// Items on the shopping list: still needed, or purchased-but-in-cart.
  /// Purchased items stay visible (in the cart) until someone restocks them,
  /// sorted by the active shopping sort.
  List<GroceryItem> get shoppingList {
    final list = _items
        .where(
          (i) =>
              i.status == GroceryStatus.needsPurchase ||
              i.status == GroceryStatus.purchased,
        )
        .toList();
    switch (_shoppingSort) {
      case ShoppingSort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case ShoppingSort.category:
        list.sort((a, b) {
          final c = a.category.compareTo(b.category);
          return c != 0
              ? c
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
      case ShoppingSort.recentlyAdded:
        list.sort((a, b) {
          final ax = a.updatedAt;
          final bx = b.updatedAt;
          if (ax == null && bx == null) return 0;
          if (ax == null) return 1;
          if (bx == null) return -1;
          return bx.compareTo(ax);
        });
        break;
    }
    return List.unmodifiable(list);
  }

  /// Shopping list grouped by category (for the grouped shopping view).
  Map<String, List<GroceryItem>> get groupedShoppingList {
    final groups = <String, List<GroceryItem>>{};
    for (final item in shoppingList) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    final keys = groups.keys.toList()..sort();
    return {for (final k in keys) k: groups[k]!};
  }

  void setShoppingSort(ShoppingSort sort) {
    if (_shoppingSort == sort) return;
    _shoppingSort = sort;
    _settings.setShoppingSortIndex(sort.index);
    notifyListeners();
  }

  void setFilter(GroceryFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _invalidateViewCache();
    notifyListeners();
  }

  void setSort(GrocerySort sort) {
    if (_sort == sort) return;
    _sort = sort;
    _invalidateViewCache();
    _settings.setSortIndex(sort.index);
    notifyListeners();
  }

  void setGroupByCategory(bool value) {
    if (_groupByCategory == value) return;
    _groupByCategory = value;
    _settings.setGroupByCategory(value);
    notifyListeners();
  }

  void setSearch(String query) {
    final trimmed = query.trim();
    if (_search == trimmed) return;
    _search = trimmed;
    _invalidateViewCache();
    notifyListeners();
  }

  /// Binds the provider to a household and starts streaming its groceries.
  void bindHousehold(String? householdId) {
    if (_householdId == householdId) return;
    _householdId = householdId;
    _sub?.cancel();
    _sub = null;
    _items = [];
    _invalidateViewCache();
    _isOffline = false;
    _hasPendingWrites = false;

    if (householdId == null) {
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();

    _sub = _service.watchGroceries(householdId).listen((snapshot) {
      final itemsChanged = !_sameItems(_items, snapshot.items);
      final flagsChanged = _isOffline != snapshot.isFromCache ||
          _hasPendingWrites != snapshot.hasPendingWrites;
      final wasLoading = _loading;

      _items = snapshot.items;
      _isOffline = snapshot.isFromCache;
      _hasPendingWrites = snapshot.hasPendingWrites;
      _loading = false;

      if (itemsChanged) _invalidateViewCache();

      // Skip the rebuild entirely when nothing observable changed — e.g. a
      // metadata-only snapshot (pending-write ack) with identical items.
      if (itemsChanged || flagsChanged || wasLoading) {
        notifyListeners();
      }
      // Only reschedule reminders when the item set actually changed.
      if (itemsChanged || wasLoading) {
        _syncReminders();
      }
    });
  }

  /// Shallow structural comparison of two grocery lists: same length, same ids
  /// in the same order, and same mutable fields that affect the UI.
  bool _sameItems(List<GroceryItem> a, List<GroceryItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.name != y.name ||
          x.category != y.category ||
          x.quantity != y.quantity ||
          x.unit != y.unit ||
          x.status != y.status ||
          x.isStaple != y.isStaple ||
          x.notes != y.notes ||
          x.imageUrl != y.imageUrl ||
          x.claimedBy != y.claimedBy ||
          x.expiryDate != y.expiryDate ||
          x.purchaseDate != y.purchaseDate ||
          x.updatedAt != y.updatedAt) {
        return false;
      }
    }
    return true;
  }

  /// Reschedules local expiry reminders to match the current items and the
  /// user's reminder preferences. Runs after each data update.
  Future<void> _syncReminders() async {
    try {
      final enabled = await _settings.getExpiryRemindersEnabled();
      await _notifications.cancelAll();
      if (!enabled) return;
      final daysBefore = await _settings.getExpiryDaysBefore();
      for (final item in _items) {
        final expiry = item.expiryDate;
        // Only remind for items still in the home that haven't expired.
        if (expiry == null || item.isExpired) continue;
        if (item.status == GroceryStatus.needsPurchase) continue;
        await _notifications.scheduleExpiryReminder(
          groceryId: item.id,
          name: item.name,
          expiryDate: expiry,
          daysBefore: daysBefore,
        );
      }
      // Schedule a daily digest summarizing items expiring within 3 days.
      await _notifications.scheduleDailyDigest(
        expiringCount: expiringSoonCount,
      );
    } catch (e) {
      debugPrint('Failed to sync reminders: $e');
    }
  }

  /// Re-applies reminders after a settings change (enabled/days-before).
  Future<void> refreshReminders() => _syncReminders();

  Future<void> addGrocery(GroceryItem item) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.addGrocery(id, item);
  }

  /// Sets an item's quantity directly without changing its status. Used for
  /// adjusting how many to buy on the shopping list.
  Future<void> setQuantity(
    GroceryItem item,
    double quantity, {
    String? updatedBy,
  }) {
    final id = _householdId;
    if (id == null) return Future.value();
    final qty = quantity < 1 ? 1.0 : quantity;
    return _service.updateGrocery(
      id,
      item.copyWith(
        quantity: qty,
        updatedBy: updatedBy,
        updatedByName: updatedBy,
      ),
    );
  }

  /// Quickly adds a name straight to the shopping list (status needs-purchase)
  /// without the full add form. Used for one-off buys not already tracked.
  Future<void> quickAddToShoppingList(
    String name, {
    String? category,
    String? unit,
    double quantity = 1,
    String? updatedBy,
  }) {
    final id = _householdId;
    if (id == null) return Future.value();
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future.value();
    return _service.addGrocery(
      id,
      GroceryItem(
        id: '',
        name: trimmed,
        category: category ?? 'Other',
        quantity: quantity,
        unit: unit ?? 'pcs',
        status: GroceryStatus.needsPurchase,
        updatedBy: updatedBy,
        updatedByName: updatedBy,
      ),
    );
  }

  Future<void> updateGrocery(GroceryItem item) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.updateGrocery(id, item);
  }

  Future<void> markPurchased(
    GroceryItem item, {
    String? updatedBy,
    double? price,
  }) async {
    final id = _householdId;
    if (id == null) return;
    await _service.updateStatus(
      id,
      item.id,
      GroceryStatus.inStock,
      updatedBy: updatedBy,
      purchaseDate: DateTime.now(),
      clearClaim: true,
    );
    await _logPurchase(item, updatedBy: updatedBy, price: price);
  }

  /// Logs a purchase event to the household's purchase history.
  Future<void> _logPurchase(
    GroceryItem item, {
    String? updatedBy,
    double? price,
  }) async {
    final id = _householdId;
    if (id == null) return;
    try {
      await _purchases.logPurchase(
        id,
        PurchaseRecord(
          id: '',
          name: item.name,
          category: item.category,
          price: price,
          purchasedBy: updatedBy,
        ),
      );
    } catch (_) {
      // Non-critical; don't block the purchase on history logging.
    }
  }

  /// Claims an item so other members know someone is buying it.
  Future<void> claimItem(
    GroceryItem item, {
    required String? uid,
    required String? name,
  }) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.setClaim(id, item.id, claimedBy: uid, claimedByName: name);
  }

  /// Releases a claim on an item.
  Future<void> unclaimItem(GroceryItem item) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.setClaim(id, item.id, claimedBy: null, claimedByName: null);
  }

  Future<void> markNeedsPurchase(GroceryItem item, {String? updatedBy}) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.updateStatus(
      id,
      item.id,
      GroceryStatus.needsPurchase,
      updatedBy: updatedBy,
    );
  }

  /// Marks a shopping-list item as purchased (kept visible in the cart section).
  Future<void> markInCart(
    GroceryItem item, {
    String? updatedBy,
    double? price,
  }) async {
    final id = _householdId;
    if (id == null) return;
    await _service.updateStatus(
      id,
      item.id,
      GroceryStatus.purchased,
      updatedBy: updatedBy,
      purchaseDate: DateTime.now(),
      clearClaim: true,
    );
    await _logPurchase(item, updatedBy: updatedBy, price: price);
  }

  /// Moves a purchased (in-cart) item back to the "needs purchase" list.
  Future<void> unmarkFromCart(GroceryItem item, {String? updatedBy}) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.updateStatus(
      id,
      item.id,
      GroceryStatus.needsPurchase,
      updatedBy: updatedBy,
    );
  }

  /// Marks every "needs purchase" item as purchased (in cart).
  Future<void> markAllInCart({String? updatedBy}) async {
    final id = _householdId;
    if (id == null) return;
    final pending = _items
        .where((i) => i.status == GroceryStatus.needsPurchase)
        .toList(growable: false);
    final now = DateTime.now();
    await Future.wait(
      pending.map(
        (item) => _service.updateStatus(
          id,
          item.id,
          GroceryStatus.purchased,
          updatedBy: updatedBy,
          purchaseDate: now,
        ),
      ),
    );
    // Log each as a purchase (no price for bulk mark-all).
    for (final item in pending) {
      await _logPurchase(item, updatedBy: updatedBy);
    }
  }

  Future<void> deleteGrocery(String groceryId) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.deleteGrocery(id, groceryId);
  }

  /// Re-adds a previously deleted item (used for undo). A new document id is
  /// created since the original was removed.
  Future<void> restoreGrocery(GroceryItem item) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.addGrocery(id, item);
  }

  /// Real-time stream of recent purchases for the active household.
  Stream<List<PurchaseRecord>> watchPurchases() {
    final id = _householdId;
    if (id == null) return Stream.value(const []);
    return _purchases.watchPurchases(id);
  }

  /// Returns item names ranked by how often the household has bought them,
  /// filtered to those matching [query] (empty query returns all, ranked).
  /// Used for smart autocomplete.
  Future<List<String>> frequentItemNames(String query, {int limit = 5}) async {
    final id = _householdId;
    if (id == null) return const [];
    final q = query.trim().toLowerCase();
    try {
      final purchases = await _purchases.getPurchases(id);
      final counts = <String, int>{};
      for (final p in purchases) {
        if (q.isEmpty || p.name.toLowerCase().contains(q)) {
          counts[p.name] = (counts[p.name] ?? 0) + 1;
        }
      }
      final sorted = counts.keys.toList()
        ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
      return sorted.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Returns a CSV of the current inventory.
  String inventoryCsv() => const ExportService().inventoryToCsv(_items);

  /// For a list of ingredient names, reports which are already in stock
  /// (status inStock/runningLow) and which are missing. Case-insensitive,
  /// matches if an inventory item name contains the ingredient or vice versa.
  ({List<String> inStock, List<String> missing}) matchIngredients(
    List<String> ingredients,
  ) {
    final stockNames = _items
        .where(
          (i) =>
              i.status == GroceryStatus.inStock ||
              i.status == GroceryStatus.runningLow,
        )
        .map((i) => i.name)
        .toList();
    return matchIngredientNames(ingredients, stockNames);
  }

  /// Adds a list of ingredient names to the shopping list (needs purchase).
  Future<void> addIngredientsToList(
    List<String> names, {
    String? updatedBy,
  }) async {
    for (final name in names) {
      await quickAddToShoppingList(name, updatedBy: updatedBy);
    }
  }

  /// Returns a CSV of the household's purchase history.
  Future<String> purchasesCsv() async {
    final id = _householdId;
    if (id == null) return '';
    final purchases = await _purchases.getPurchases(id);
    return const ExportService().purchasesToCsv(purchases);
  }

  /// Estimates the total cost of the current "to buy" items using the most
  /// recent known price per item name from purchase history. Returns null if
  /// no prices are known. Also reports how many items had a known price.
  Future<({double total, int priced, int totalItems})?>
  estimateShoppingTotal() async {
    final id = _householdId;
    if (id == null) return null;
    final toBuy = _items
        .where((i) => i.status == GroceryStatus.needsPurchase)
        .toList(growable: false);
    if (toBuy.isEmpty) return null;
    try {
      final purchases = await _purchases.getPurchases(id);
      // Most recent price per item name (purchases are newest-first).
      final lastPrice = <String, double>{};
      for (final p in purchases) {
        if (p.price != null && !lastPrice.containsKey(p.name.toLowerCase())) {
          lastPrice[p.name.toLowerCase()] = p.price!;
        }
      }
      double total = 0;
      int priced = 0;
      for (final item in toBuy) {
        final price = lastPrice[item.name.toLowerCase()];
        if (price != null) {
          total += price * item.quantity;
          priced++;
        }
      }
      return (total: total, priced: priced, totalItems: toBuy.length);
    } catch (_) {
      return null;
    }
  }

  /// Suggests items the household is likely due to re-buy, based on how
  /// regularly they've been purchased and how long since the last purchase.
  ///
  /// Logic: for each item name with >= 3 purchases, compute the average
  /// interval between purchases. If days-since-last-purchase >= average
  /// interval, it's "due". Items already in stock low / needs-purchase or
  /// currently on the list are excluded. Returns suggestions sorted by how
  /// overdue they are.
  Future<List<LowStockSuggestion>> lowStockSuggestions({int limit = 5}) async {
    final id = _householdId;
    if (id == null) return const [];
    try {
      final purchases = await _purchases.getPurchases(id, limit: 1000);
      // Group purchase timestamps by item name.
      final byName = <String, List<DateTime>>{};
      for (final p in purchases) {
        final when = p.purchasedAt;
        if (when == null) continue;
        byName.putIfAbsent(p.name, () => []).add(when);
      }

      // Names already needing purchase / on the list — don't re-suggest.
      final onList = _items
          .where(
            (i) =>
                i.status == GroceryStatus.needsPurchase ||
                i.status == GroceryStatus.purchased,
          )
          .map((i) => i.name.toLowerCase())
          .toSet();

      final now = DateTime.now();
      final suggestions = <LowStockSuggestion>[];

      byName.forEach((name, dates) {
        if (dates.length < 3) return; // need a pattern
        if (onList.contains(name.toLowerCase())) return;
        dates.sort(); // oldest first
        // Average interval between consecutive purchases, in days.
        var totalDays = 0;
        for (var i = 1; i < dates.length; i++) {
          totalDays += dates[i].difference(dates[i - 1]).inDays;
        }
        final avgInterval = totalDays / (dates.length - 1);
        if (avgInterval <= 0) return;
        final daysSinceLast = now.difference(dates.last).inDays;
        if (daysSinceLast >= avgInterval) {
          suggestions.add(
            LowStockSuggestion(
              name: name,
              avgIntervalDays: avgInterval.round(),
              daysSinceLast: daysSinceLast,
              overdueBy: (daysSinceLast - avgInterval).round(),
            ),
          );
        }
      });

      suggestions.sort((a, b) => b.overdueBy.compareTo(a.overdueBy));
      return suggestions.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Adds a suggested item to the shopping list. If an item with that name
  /// already exists in inventory, it's flagged needs-purchase; otherwise a new
  /// needs-purchase item is created.
  Future<void> addSuggestionToList(
    LowStockSuggestion suggestion, {
    String? updatedBy,
  }) async {
    final id = _householdId;
    if (id == null) return;
    GroceryItem? existing;
    for (final i in _items) {
      if (i.name.toLowerCase() == suggestion.name.toLowerCase()) {
        existing = i;
        break;
      }
    }
    if (existing != null) {
      await _service.updateStatus(
        id,
        existing.id,
        GroceryStatus.needsPurchase,
        updatedBy: updatedBy,
      );
    } else {
      await _service.addGrocery(
        id,
        GroceryItem(
          id: '',
          name: suggestion.name,
          category: 'Other',
          quantity: 1,
          unit: 'pcs',
          status: GroceryStatus.needsPurchase,
          updatedBy: updatedBy,
          updatedByName: updatedBy,
        ),
      );
    }
  }

  /// Deletes multiple items. Returns the deleted items so callers can offer
  /// an undo (restore).
  Future<List<GroceryItem>> deleteItems(Iterable<GroceryItem> items) async {
    final id = _householdId;
    if (id == null) return const [];
    final list = items.toList(growable: false);
    await Future.wait(list.map((i) => _service.deleteGrocery(id, i.id)));
    return list;
  }

  /// Restores multiple previously deleted items (undo for bulk delete).
  Future<void> restoreItems(Iterable<GroceryItem> items) async {
    final id = _householdId;
    if (id == null) return;
    await Future.wait(items.map((i) => _service.addGrocery(id, i)));
  }

  /// Marks multiple items as "needs purchase" (bulk add to shopping list).
  Future<void> addItemsToShoppingList(
    Iterable<GroceryItem> items, {
    String? updatedBy,
  }) async {
    final id = _householdId;
    if (id == null) return;
    await Future.wait(
      items.map(
        (i) => _service.updateStatus(
          id,
          i.id,
          GroceryStatus.needsPurchase,
          updatedBy: updatedBy,
        ),
      ),
    );
  }

  /// Changes the category of multiple items at once.
  Future<void> changeCategory(
    Iterable<GroceryItem> items,
    String category, {
    String? updatedBy,
  }) async {
    final id = _householdId;
    if (id == null) return;
    await Future.wait(
      items.map(
        (i) => _service.updateGrocery(
          id,
          i.copyWith(
            category: category,
            updatedBy: updatedBy,
            updatedByName: updatedBy,
          ),
        ),
      ),
    );
  }

  /// Adjusts an item's quantity by [delta] (clamped at 0). When the quantity
  /// reaches 0, the item is automatically flagged as "needs purchase". Staple
  /// items are flagged as soon as they run low so they return to the list.
  Future<void> adjustQuantity(
    GroceryItem item,
    double delta, {
    String? updatedBy,
  }) {
    final id = _householdId;
    if (id == null) return Future.value();
    final newQty = (item.quantity + delta).clamp(0, double.infinity).toDouble();
    final GroceryStatus newStatus;
    if (newQty == 0) {
      newStatus = GroceryStatus.needsPurchase;
    } else if (item.isStaple && newQty <= 1) {
      // Staples should reappear on the shopping list before fully running out.
      newStatus = GroceryStatus.needsPurchase;
    } else if (newQty <= 1 && item.status == GroceryStatus.inStock) {
      newStatus = GroceryStatus.runningLow;
    } else {
      newStatus = item.status;
    }
    final updated = item.copyWith(
      quantity: newQty,
      status: newStatus,
      updatedBy: updatedBy,
      updatedByName: updatedBy,
    );
    return _service.updateGrocery(id, updated);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
