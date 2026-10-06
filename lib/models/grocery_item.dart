import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle status of a grocery item within the household.
enum GroceryStatus {
  inStock,
  runningLow,
  needsPurchase,
  purchased,
}

extension GroceryStatusX on GroceryStatus {
  /// Value persisted to Firestore.
  String get value {
    switch (this) {
      case GroceryStatus.inStock:
        return 'in_stock';
      case GroceryStatus.runningLow:
        return 'running_low';
      case GroceryStatus.needsPurchase:
        return 'needs_purchase';
      case GroceryStatus.purchased:
        return 'purchased';
    }
  }

  /// Human readable label for the UI.
  String get label {
    switch (this) {
      case GroceryStatus.inStock:
        return 'In stock';
      case GroceryStatus.runningLow:
        return 'Running low';
      case GroceryStatus.needsPurchase:
        return 'Needs purchase';
      case GroceryStatus.purchased:
        return 'Purchased';
    }
  }

  static GroceryStatus fromValue(String? raw) {
    switch (raw) {
      case 'running_low':
        return GroceryStatus.runningLow;
      case 'needs_purchase':
        return GroceryStatus.needsPurchase;
      case 'purchased':
        return GroceryStatus.purchased;
      case 'in_stock':
      default:
        return GroceryStatus.inStock;
    }
  }
}

/// A single grocery item tracked by a household.
class GroceryItem {
  final String id;
  final String name;
  final String category;
  final double quantity;
  final String unit;
  final GroceryStatus status;
  final DateTime? purchaseDate;
  final DateTime? expiryDate;
  final bool isStaple;
  final String? notes;
  final String? imageUrl;
  final List<String> photos;
  final String? claimedBy;
  final String? claimedByName;
  final String? updatedBy;
  final String? updatedByName;
  final DateTime? updatedAt;

  const GroceryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.status,
    this.purchaseDate,
    this.expiryDate,
    this.isStaple = false,
    this.notes,
    this.imageUrl,
    this.photos = const [],
    this.claimedBy,
    this.claimedByName,
    this.updatedBy,
    this.updatedByName,
    this.updatedAt,
  });

  /// Whether the item has a non-empty note.
  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  /// Whether the item has a label/card image.
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// Maximum number of user reference photos (excluding the label image).
  static const int maxPhotos = 2;

  /// Whether someone has claimed to buy this item.
  bool get isClaimed => claimedBy != null && claimedBy!.isNotEmpty;

  /// Whether the item is already expired (expiry date in the past).
  bool get isExpired {
    final expiry = expiryDate;
    if (expiry == null) return false;
    return expiry.isBefore(DateTime.now());
  }

  /// Whether the item expires within the next [days] days.
  bool expiresWithin(int days) {
    final expiry = expiryDate;
    if (expiry == null) return false;
    final threshold = DateTime.now().add(Duration(days: days));
    return !isExpired && expiry.isBefore(threshold);
  }

  /// Days remaining until expiry (negative if already expired).
  int? get daysUntilExpiry {
    final expiry = expiryDate;
    if (expiry == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
    return expiryDay.difference(today).inDays;
  }

  factory GroceryItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return GroceryItem(
      id: doc.id,
      name: (data['name'] ?? '') as String,
      category: (data['category'] ?? 'Other') as String,
      quantity: (data['quantity'] as num?)?.toDouble() ?? 1,
      unit: (data['unit'] ?? 'pcs') as String,
      status: GroceryStatusX.fromValue(data['status'] as String?),
      purchaseDate: (data['purchaseDate'] as Timestamp?)?.toDate(),
      expiryDate: (data['expiryDate'] as Timestamp?)?.toDate(),
      isStaple: (data['isStaple'] as bool?) ?? false,
      notes: data['notes'] as String?,
      imageUrl: data['imageUrl'] as String?,
      photos: ((data['photos'] as List?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
      claimedBy: data['claimedBy'] as String?,
      claimedByName: data['claimedByName'] as String?,
      updatedBy: data['updatedBy'] as String?,
      updatedByName: data['updatedByName'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category,
      'quantity': quantity,
      'unit': unit,
      'status': status.value,
      'purchaseDate':
          purchaseDate == null ? null : Timestamp.fromDate(purchaseDate!),
      'expiryDate':
          expiryDate == null ? null : Timestamp.fromDate(expiryDate!),
      'isStaple': isStaple,
      'notes': notes,
      'imageUrl': imageUrl,
      'photos': photos,
      'claimedBy': claimedBy,
      'claimedByName': claimedByName,
      'updatedBy': updatedBy,
      'updatedByName': updatedByName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  GroceryItem copyWith({
    String? name,
    String? category,
    double? quantity,
    String? unit,
    GroceryStatus? status,
    DateTime? purchaseDate,
    DateTime? expiryDate,
    bool? isStaple,
    String? notes,
    bool clearNotes = false,
    String? imageUrl,
    bool clearImage = false,
    List<String>? photos,
    String? claimedBy,
    String? claimedByName,
    bool clearClaim = false,
    String? updatedBy,
    String? updatedByName,
  }) {
    return GroceryItem(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      status: status ?? this.status,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      expiryDate: expiryDate ?? this.expiryDate,
      isStaple: isStaple ?? this.isStaple,
      notes: clearNotes ? null : (notes ?? this.notes),
      imageUrl: clearImage ? null : (imageUrl ?? this.imageUrl),
      photos: photos ?? this.photos,
      claimedBy: clearClaim ? null : (claimedBy ?? this.claimedBy),
      claimedByName: clearClaim ? null : (claimedByName ?? this.claimedByName),
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
      updatedAt: updatedAt,
    );
  }

  /// A short "who did what, when" line, e.g. "Alex · 2h ago".
  /// Returns null if there's nothing to show.
  String? get activityLabel {
    // Prefer the explicit display name; fall back to updatedBy, stripping any
    // email domain so legacy records show just the local part.
    var who = (updatedByName?.trim().isNotEmpty ?? false)
        ? updatedByName!.trim()
        : (updatedBy?.trim() ?? '');
    if (who.contains('@')) who = who.split('@').first;
    final when = updatedAt;
    final ago = when == null ? null : _relativeTime(when);
    if (who.isEmpty) {
      return ago;
    }
    return ago == null ? who : '$who · $ago';
  }

  static String _relativeTime(DateTime time) {
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
}
