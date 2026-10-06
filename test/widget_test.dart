import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stockhome/models/grocery_item.dart';
import 'package:stockhome/widgets/grocery_tile.dart';

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

    test('notes: set, preserve, and clear', () {
      const item = GroceryItem(
        id: 'e',
        name: 'Paneer',
        category: 'Dairy & Eggs',
        quantity: 1,
        unit: 'pack',
        status: GroceryStatus.inStock,
      );
      expect(item.hasNotes, isFalse);

      final noted = item.copyWith(notes: 'Top shelf of fridge');
      expect(noted.hasNotes, isTrue);
      expect(noted.notes, 'Top shelf of fridge');

      // Unrelated copyWith preserves the note.
      expect(noted.copyWith(quantity: 2).hasNotes, isTrue);

      // clearNotes removes it.
      final cleared = noted.copyWith(clearNotes: true);
      expect(cleared.hasNotes, isFalse);
      expect(cleared.notes, isNull);
    });

    test('image: set, preserve, and clear', () {
      const item = GroceryItem(
        id: 'f',
        name: 'Aam (Mango)',
        category: 'Fruits & Vegetables',
        quantity: 6,
        unit: 'pcs',
        status: GroceryStatus.inStock,
      );
      expect(item.hasImage, isFalse);

      final withImage =
          item.copyWith(imageUrl: 'https://example.com/mango.jpg');
      expect(withImage.hasImage, isTrue);
      expect(withImage.imageUrl, 'https://example.com/mango.jpg');

      // Unrelated copyWith preserves the image.
      expect(withImage.copyWith(quantity: 3).hasImage, isTrue);

      // clearImage removes it.
      final cleared = withImage.copyWith(clearImage: true);
      expect(cleared.hasImage, isFalse);
      expect(cleared.imageUrl, isNull);
    });

    test('photos: default empty, set, and preserve', () {
      const item = GroceryItem(
        id: 'g',
        name: 'Atta (Wheat Flour)',
        category: 'Pantry & Dry Goods',
        quantity: 5,
        unit: 'kg',
        status: GroceryStatus.inStock,
      );
      expect(item.photos, isEmpty);
      expect(GroceryItem.maxPhotos, 2);

      final withPhotos = item.copyWith(photos: [
        'https://example.com/a.jpg',
        'https://example.com/b.jpg',
      ]);
      expect(withPhotos.photos.length, 2);

      // Unrelated copyWith preserves photos.
      expect(withPhotos.copyWith(quantity: 10).photos.length, 2);

      // Can be replaced with an empty list.
      expect(withPhotos.copyWith(photos: const []).photos, isEmpty);
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
