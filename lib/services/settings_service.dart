import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight persisted app settings.
class SettingsService {
  static const _kExpiryRemindersEnabled = 'expiry_reminders_enabled';
  static const _kExpiryDaysBefore = 'expiry_days_before';
  static const _kSortIndex = 'inventory_sort_index';
  static const _kGroupByCategory = 'inventory_group_by_category';

  Future<bool> getExpiryRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kExpiryRemindersEnabled) ?? true;
  }

  Future<void> setExpiryRemindersEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kExpiryRemindersEnabled, value);
  }

  Future<int> getExpiryDaysBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kExpiryDaysBefore) ?? 2;
  }

  Future<void> setExpiryDaysBefore(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kExpiryDaysBefore, days);
  }

  Future<int> getSortIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kSortIndex) ?? 0;
  }

  Future<void> setSortIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSortIndex, index);
  }

  Future<bool> getGroupByCategory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGroupByCategory) ?? false;
  }

  Future<void> setGroupByCategory(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGroupByCategory, value);
  }
}
