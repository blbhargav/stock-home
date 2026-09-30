import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/grocery_item.dart';

/// Groceries plus the sync metadata of the snapshot they came from.
class GrocerySnapshot {
  const GrocerySnapshot({
    required this.items,
    required this.isFromCache,
    required this.hasPendingWrites,
  });

  final List<GroceryItem> items;

  /// True when the data was served from the local cache (i.e. offline or not
  /// yet reached the server).
  final bool isFromCache;

  /// True when there are local writes not yet acknowledged by the server.
  final bool hasPendingWrites;
}

/// Handles CRUD and real-time streaming of groceries for a household.
///
/// Firestore layout:
///   households/{householdId}/groceries/{groceryId}
class GroceryService {
  GroceryService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _groceries(String householdId) {
    return _db
        .collection('households')
        .doc(householdId)
        .collection('groceries');
  }

  /// Real-time stream of all groceries in the household, ordered by name.
  /// Includes metadata changes so offline / pending-sync state is reported.
  Stream<GrocerySnapshot> watchGroceries(String householdId) {
    return _groceries(householdId)
        .orderBy('name')
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) => GrocerySnapshot(
              items: snapshot.docs
                  .map(GroceryItem.fromDoc)
                  .toList(growable: false),
              isFromCache: snapshot.metadata.isFromCache,
              hasPendingWrites: snapshot.metadata.hasPendingWrites,
            ));
  }

  Future<void> addGrocery(String householdId, GroceryItem item) {
    return _groceries(householdId).add(item.toMap());
  }

  Future<void> updateGrocery(String householdId, GroceryItem item) {
    return _groceries(householdId).doc(item.id).update(item.toMap());
  }

  Future<void> updateStatus(
    String householdId,
    String groceryId,
    GroceryStatus status, {
    String? updatedBy,
    DateTime? purchaseDate,
    bool clearClaim = false,
  }) {
    final data = <String, dynamic>{
      'status': status.value,
      'updatedBy': updatedBy,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (purchaseDate != null) {
      data['purchaseDate'] = Timestamp.fromDate(purchaseDate);
    }
    if (clearClaim) {
      data['claimedBy'] = null;
      data['claimedByName'] = null;
    }
    return _groceries(householdId).doc(groceryId).update(data);
  }

  Future<void> deleteGrocery(String householdId, String groceryId) {
    return _groceries(householdId).doc(groceryId).delete();
  }

  /// Sets or clears who has claimed to buy an item.
  Future<void> setClaim(
    String householdId,
    String groceryId, {
    required String? claimedBy,
    required String? claimedByName,
  }) {
    return _groceries(householdId).doc(groceryId).update({
      'claimedBy': claimedBy,
      'claimedByName': claimedByName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
