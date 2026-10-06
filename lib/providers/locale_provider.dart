import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Holds the app's selected locale (null = follow system), persisted.
class LocaleProvider extends ChangeNotifier {
  LocaleProvider({SettingsService? settings})
    : _settings = settings ?? SettingsService() {
    _load();
  }

  final SettingsService _settings;

  Locale? _locale;
  Locale? get locale => _locale;

  /// Supported locales offered in the language picker.
  static const supported = <Locale>[Locale('en'), Locale('te'), Locale('kn')];

  static String labelFor(Locale? locale) {
    switch (locale?.languageCode) {
      case 'te':
        return 'తెలుగు (Telugu)';
      case 'kn':
        return 'ಕನ್ನಡ (Kannada)';
      case 'en':
        return 'English';
      default:
        return 'System default';
    }
  }

  Future<void> _load() async {
    final code = await _settings.getLanguageCode();
    _locale = (code == null || code.isEmpty) ? null : Locale(code);
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    await _settings.setLanguageCode(locale?.languageCode);
  }
}
