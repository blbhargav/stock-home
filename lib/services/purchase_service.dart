import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/purchase_record.dart';

/// Logs and reads purchase history for a household.
///
/// Firestore layout: households/{householdId}/purchases/{purchaseId}
class PurchaseService {
  PurchaseService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _purchases(String householdId) {
    return _db
        .collection('households')
        .doc(householdId)
        .collection('purchases');
  }

  Future<void> logPurchase(String householdId, PurchaseRecord record) {
    return _purchases(householdId).add(record.toMap());
  }

  /// Streams recent purchases (most recent first), capped at [limit].
  Stream<List<PurchaseRecord>> watchPurchases(
    String householdId, {
    int limit = 200,
  }) {
    return _purchases(householdId)
        .orderBy('purchasedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map(PurchaseRecord.fromDoc).toList(growable: false));
  }

  /// One-shot fetch of purchases for computing frequency/spend.
  Future<List<PurchaseRecord>> getPurchases(
    String householdId, {
    int limit = 500,
  }) async {
    final snap = await _purchases(householdId)
        .orderBy('purchasedAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(PurchaseRecord.fromDoc).toList(growable: false);
  }
}
