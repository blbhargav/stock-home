import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Holds the app's theme mode (system / light / dark), persisted to settings.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({SettingsService? settings})
    : _settings = settings ?? SettingsService() {
    _load();
  }

  final SettingsService _settings;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  Future<void> _load() async {
    final index = await _settings.getThemeModeIndex();
    _themeMode = _fromIndex(index);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _settings.setThemeModeIndex(_toIndex(mode));
  }

  static ThemeMode _fromIndex(int index) {
    switch (index) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static int _toIndex(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 1;
      case ThemeMode.dark:
        return 2;
      case ThemeMode.system:
        return 0;
    }
  }
}
