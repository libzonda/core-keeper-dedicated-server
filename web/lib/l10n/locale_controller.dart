import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  zh('简体中文', Locale('zh', 'CN')),
  en('English', Locale('en', 'US')),
  es('Español', Locale('es', 'ES')),
  fr('Français', Locale('fr', 'FR')),
  ja('日本語', Locale('ja', 'JP')),
  ko('한국어', Locale('ko', 'KR')),
  ru('Русский', Locale('ru', 'RU'));

  final String label;
  final Locale locale;

  const AppLanguage(this.label, this.locale);

  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (lang) => lang.locale.languageCode == code,
      orElse: () => AppLanguage.zh,
    );
  }
}

class LocaleController extends ValueNotifier<AppLanguage> {
  LocaleController._() : super(AppLanguage.zh);

  static final LocaleController instance = LocaleController._();

  static const String _prefKey = 'ck_app_language';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_prefKey);
      if (savedCode != null && savedCode.isNotEmpty) {
        value = AppLanguage.fromCode(savedCode);
      }
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage language) async {
    value = language;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, language.locale.languageCode);
    } catch (_) {}
  }
}

