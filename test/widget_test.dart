import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pantrypal/models/grocery_item.dart';
import 'package:pantrypal/widgets/grocery_tile.dart';

void main() {
  group('GroceryItem status & expiry logic', () {
    test('isExpired is true when expiry is in the past', () {
      final item = GroceryItem(
        id: '1',
        name: 'Milk',
        category: 'Dairy & Eggs',
        quantity: 1,
        unit: 'L',
        status: GroceryStatus.inStock,
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(item.isExpired, isTrue);
      expect(item.expiresWithin(3), isFalse);
    });

    test('expiresWithin detects items close to expiry', () {
      final item = GroceryItem(
        id: '2',
        name: 'Yogurt',
        category: 'Dairy & Eggs',
        quantity: 2,
        unit: 'pcs',
        status: GroceryStatus.inStock,
        expiryDate: DateTime.now().add(const Duration(days: 2)),
      );
      expect(item.isExpired, isFalse);
      expect(item.expiresWithin(3), isTrue);
      expect(item.expiresWithin(1), isFalse);
    });

    test('status value round-trips through fromValue', () {
      for (final status in GroceryStatus.values) {
        expect(GroceryStatusX.fromValue(status.value), status);
      }
    });

    test('activityLabel combines who and relative time', () {
      final item = GroceryItem(
        id: 'a',
        name: 'Milk',
        category: 'Dairy & Eggs',
        quantity: 1,
        unit: 'L',
        status: GroceryStatus.inStock,
        updatedBy: 'Alex',
        updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(item.activityLabel, 'Alex · 2h ago');
    });

    test('activityLabel is null when no data', () {
      const item = GroceryItem(
        id: 'b',
        name: 'Rice',
        category: 'Pantry & Dry Goods',
        quantity: 5,
        unit: 'kg',
        status: GroceryStatus.inStock,
      );
      expect(item.activityLabel, isNull);
    });

    test('isStaple defaults to false and is preserved by copyWith', () {
      const item = GroceryItem(
        id: 'c',
        name: 'Milk',
        category: 'Dairy & Eggs',
        quantity: 1,
        unit: 'L',
        status: GroceryStatus.inStock,
      );
      expect(item.isStaple, isFalse);
      final staple = item.copyWith(isStaple: true);
      expect(staple.isStaple, isTrue);
      // copyWith without the arg keeps the value.
      expect(staple.copyWith(quantity: 2).isStaple, isTrue);
    });

    test('claim state: set, preserve, and clear', () {
      const item = GroceryItem(
        id: 'd',
        name: 'Eggs',
        category: 'Dairy & Eggs',
        quantity: 1,
        unit: 'dozen',
        status: GroceryStatus.needsPurchase,
      );
      expect(item.isClaimed, isFalse);

      final claimed =
          item.copyWith(claimedBy: 'uid1', claimedByName: 'Sam');
      expect(claimed.isClaimed, isTrue);
      expect(claimed.claimedByName, 'Sam');

      // Unrelated copyWith preserves the claim.
      expect(claimed.copyWith(quantity: 2).isClaimed, isTrue);

      // clearClaim removes it.
      final cleared = claimed.copyWith(clearClaim: true);
      expect(cleared.isClaimed, isFalse);
      expect(cleared.claimedByName, isNull);
    });
  });

  testWidgets('GroceryTile renders name and status', (tester) async {
    final item = GroceryItem(
      id: '3',
      name: 'Apples',
      category: 'Fruits & Vegetables',
      quantity: 6,
      unit: 'pcs',
      status: GroceryStatus.needsPurchase,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroceryTile(
            item: item,
            onTap: () {},
            onMarkPurchased: () {},
            onMarkNeedsPurchase: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.text('Apples'), findsOneWidget);
    expect(find.text('Needs purchase'), findsOneWidget);
  });
}
