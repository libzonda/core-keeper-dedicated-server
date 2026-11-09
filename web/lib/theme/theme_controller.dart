import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  dark,
  light;

  String label([AppLocalizations? l10n]) => switch (this) {
    dark => l10n?.themeDark ?? 'Dark',
    light => l10n?.themeLight ?? 'Light',
  };

  IconData get icon => switch (this) {
    dark => Icons.dark_mode_rounded,
    light => Icons.light_mode_rounded,
  };
}

class ThemeController extends ValueNotifier<AppThemeMode> {
  ThemeController._() : super(AppThemeMode.dark);

  static final ThemeController instance = ThemeController._();

  static const String _prefKey = 'ck_theme_mode';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'light') {
        value = AppThemeMode.light;
      } else {
        value = AppThemeMode.dark;
      }
    } catch (_) {}
  }

  Future<void> setMode(AppThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {}
  }

  Future<void> toggle() async {
    final next = value == AppThemeMode.dark ? AppThemeMode.light : AppThemeMode.dark;
    await setMode(next);
  }
}
