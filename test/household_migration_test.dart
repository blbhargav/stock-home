import 'package:flutter_test/flutter_test.dart';
import 'package:stockhome/services/household_service.dart';

void main() {
  group('parseUserHouseholds (multi-household migration)', () {
    test('null profile yields empty', () {
      final r = parseUserHouseholds(null);
      expect(r.ids, isEmpty);
      expect(r.active, isNull);
    });

    test('legacy single householdId migrates into the list', () {
      final r = parseUserHouseholds({'householdId': 'abc'});
      expect(r.ids, ['abc']);
      expect(r.active, 'abc');
    });

    test('empty legacy string is ignored', () {
      final r = parseUserHouseholds({'householdId': ''});
      expect(r.ids, isEmpty);
      expect(r.active, isNull);
    });

    test('householdIds list is used as-is', () {
      final r = parseUserHouseholds({
        'householdIds': ['a', 'b'],
        'activeHouseholdId': 'b',
      });
      expect(r.ids, ['a', 'b']);
      expect(r.active, 'b');
    });

    test('active defaults to first when missing', () {
      final r = parseUserHouseholds({
        'householdIds': ['a', 'b'],
      });
      expect(r.active, 'a');
    });

    test('active defaults to first when it is not in the list', () {
      final r = parseUserHouseholds({
        'householdIds': ['a', 'b'],
        'activeHouseholdId': 'zzz',
      });
      expect(r.active, 'a');
    });

    test('list takes precedence over legacy field', () {
      // This is the regression case: a user who already migrated must not
      // lose their list when a legacy mirror still exists.
      final r = parseUserHouseholds({
        'householdIds': ['new1', 'old1'],
        'activeHouseholdId': 'new1',
        'householdId': 'new1',
      });
      expect(r.ids, ['new1', 'old1']);
      expect(r.active, 'new1');
    });

    test('non-string entries in list are filtered out', () {
      final r = parseUserHouseholds({
        'householdIds': ['a', 123, null, 'b'],
      });
      expect(r.ids, ['a', 'b']);
    });
  });
}
