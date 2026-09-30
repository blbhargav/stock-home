import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/grocery_item.dart';
import '../services/grocery_service.dart';
import '../services/notification_service.dart';
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

/// Streams and mutates the grocery list for the active household.
class GroceryProvider extends ChangeNotifier {
  GroceryProvider({
    GroceryService? service,
    NotificationService? notifications,
    SettingsService? settings,
  })  : _service = service ?? GroceryService(),
        _notifications = notifications ?? NotificationService.instance,
        _settings = settings ?? SettingsService() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final sortIndex = await _settings.getSortIndex();
      final group = await _settings.getGroupByCategory();
      _sort = GrocerySort.values[
          sortIndex.clamp(0, GrocerySort.values.length - 1)];
      _groupByCategory = group;
      notifyListeners();
    } catch (_) {
      // Ignore; defaults are fine.
    }
  }

  final GroceryService _service;
  final NotificationService _notifications;
  final SettingsService _settings;

  String? _householdId;
  StreamSubscription<GrocerySnapshot>? _sub;

  List<GroceryItem> _items = [];
  bool _loading = false;
  bool _isOffline = false;
  bool _hasPendingWrites = false;
  GroceryFilter _filter = GroceryFilter.all;
  GrocerySort _sort = GrocerySort.name;
  bool _groupByCategory = false;
  String _search = '';

  List<GroceryItem> get allItems => List.unmodifiable(_items);
  bool get loading => _loading;

  /// True when data is being served from the local cache (offline).
  bool get isOffline => _isOffline;

  /// True when local changes are waiting to sync to the server.
  bool get hasPendingWrites => _hasPendingWrites;

  GroceryFilter get filter => _filter;
  GrocerySort get sort => _sort;
  bool get groupByCategory => _groupByCategory;
  String get search => _search;

  /// Number of items that need to be purchased.
  int get needsPurchaseCount =>
      _items.where((i) => i.status == GroceryStatus.needsPurchase).length;

  /// Number of items expiring within 3 days (and not yet expired).
  int get expiringSoonCount =>
      _items.where((i) => i.expiresWithin(3)).length;

  /// Number of already expired items.
  int get expiredCount => _items.where((i) => i.isExpired).length;

  /// Items after applying the active filter and search query.
  List<GroceryItem> get visibleItems {
    Iterable<GroceryItem> result = _items;

    switch (_filter) {
      case GroceryFilter.all:
        break;
      case GroceryFilter.inStock:
        result = result.where((i) =>
            i.status == GroceryStatus.inStock ||
            i.status == GroceryStatus.runningLow);
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
      result = result.where((i) =>
          i.name.toLowerCase().contains(q) ||
          i.category.toLowerCase().contains(q));
    }

    final list = result.toList();
    _applySort(list);
    return List.unmodifiable(list);
  }

  void _applySort(List<GroceryItem> list) {
    switch (_sort) {
      case GrocerySort.name:
        list.sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
    final groups = <String, List<GroceryItem>>{};
    for (final item in visibleItems) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    final sortedKeys = groups.keys.toList()..sort();
    return {for (final k in sortedKeys) k: groups[k]!};
  }

  /// Items on the shopping list: still needed, or purchased-but-in-cart.
  /// Purchased items stay visible (in the cart) until someone restocks them.
  List<GroceryItem> get shoppingList => _items
      .where((i) =>
          i.status == GroceryStatus.needsPurchase ||
          i.status == GroceryStatus.purchased)
      .toList(growable: false);

  void setFilter(GroceryFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    notifyListeners();
  }

  void setSort(GrocerySort sort) {
    if (_sort == sort) return;
    _sort = sort;
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
    _search = query.trim();
    notifyListeners();
  }

  /// Binds the provider to a household and starts streaming its groceries.
  void bindHousehold(String? householdId) {
    if (_householdId == householdId) return;
    _householdId = householdId;
    _sub?.cancel();
    _sub = null;
    _items = [];
    _isOffline = false;
    _hasPendingWrites = false;

    if (householdId == null) {
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();

    _sub = _service.watchGroceries(householdId).listen((snapshot) {
      _items = snapshot.items;
      _isOffline = snapshot.isFromCache;
      _hasPendingWrites = snapshot.hasPendingWrites;
      _loading = false;
      notifyListeners();
      // Keep expiry reminders in sync with the latest data.
      _syncReminders();
    });
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

  Future<void> updateGrocery(GroceryItem item) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.updateGrocery(id, item);
  }

  Future<void> markPurchased(GroceryItem item, {String? updatedBy}) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.updateStatus(
      id,
      item.id,
      GroceryStatus.inStock,
      updatedBy: updatedBy,
      purchaseDate: DateTime.now(),
      clearClaim: true,
    );
  }

  /// Claims an item so other members know someone is buying it.
  Future<void> claimItem(GroceryItem item,
      {required String? uid, required String? name}) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.setClaim(
      id,
      item.id,
      claimedBy: uid,
      claimedByName: name,
    );
  }

  /// Releases a claim on an item.
  Future<void> unclaimItem(GroceryItem item) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.setClaim(
      id,
      item.id,
      claimedBy: null,
      claimedByName: null,
    );
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
  Future<void> markInCart(GroceryItem item, {String? updatedBy}) {
    final id = _householdId;
    if (id == null) return Future.value();
    return _service.updateStatus(
      id,
      item.id,
      GroceryStatus.purchased,
      updatedBy: updatedBy,
      purchaseDate: DateTime.now(),
      clearClaim: true,
    );
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
    await Future.wait(pending.map((item) => _service.updateStatus(
          id,
          item.id,
          GroceryStatus.purchased,
          updatedBy: updatedBy,
          purchaseDate: now,
        )));
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
    );
    return _service.updateGrocery(id, updated);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
