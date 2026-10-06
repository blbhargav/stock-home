import '../models/grocery_item.dart';
import '../models/purchase_record.dart';

/// Builds CSV exports of inventory and purchase history.
class ExportService {
  const ExportService();

  String _escape(String value) {
    // Quote fields containing comma, quote or newline; double embedded quotes.
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String _fmtDate(DateTime? d) =>
      d == null ? '' : d.toIso8601String().split('T').first;

  String _trimQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// CSV of the current inventory.
  String inventoryToCsv(List<GroceryItem> items) {
    final rows = <String>[
      'Name,Category,Quantity,Unit,Status,Purchase Date,Expiry Date,Staple,Notes',
    ];
    for (final i in items) {
      rows.add([
        _escape(i.name),
        _escape(i.category),
        _trimQty(i.quantity),
        _escape(i.unit),
        _escape(i.status.label),
        _fmtDate(i.purchaseDate),
        _fmtDate(i.expiryDate),
        i.isStaple ? 'Yes' : 'No',
        _escape(i.notes ?? ''),
      ].join(','));
    }
    return rows.join('\n');
  }

  /// CSV of purchase history.
  String purchasesToCsv(List<PurchaseRecord> purchases) {
    final rows = <String>['Name,Category,Price,Purchased By,Date'];
    for (final p in purchases) {
      rows.add([
        _escape(p.name),
        _escape(p.category),
        p.price?.toStringAsFixed(2) ?? '',
        _escape(p.purchasedBy ?? ''),
        _fmtDate(p.purchasedAt),
      ].join(','));
    }
    return rows.join('\n');
  }
}
