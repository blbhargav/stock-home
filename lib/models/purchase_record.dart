import 'package:cloud_firestore/cloud_firestore.dart';

/// A single purchase event, logged when an item is marked purchased.
///
/// Firestore layout: households/{householdId}/purchases/{purchaseId}
class PurchaseRecord {
  const PurchaseRecord({
    required this.id,
    required this.name,
    required this.category,
    this.price,
    this.purchasedBy,
    this.purchasedAt,
  });

  final String id;
  final String name;
  final String category;
  final double? price;
  final String? purchasedBy;
  final DateTime? purchasedAt;

  factory PurchaseRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return PurchaseRecord(
      id: doc.id,
      name: (data['name'] ?? '') as String,
      category: (data['category'] ?? 'Other') as String,
      price: (data['price'] as num?)?.toDouble(),
      purchasedBy: data['purchasedBy'] as String?,
      purchasedAt: (data['purchasedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category,
    'price': price,
    'purchasedBy': purchasedBy,
    'purchasedAt': FieldValue.serverTimestamp(),
  };
}
