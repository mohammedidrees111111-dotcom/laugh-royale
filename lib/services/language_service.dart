import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static final ValueNotifier<Locale> localeNotifier =
      ValueNotifier(const Locale('en'));

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('language') ?? 'en';
    localeNotifier.value =
        lang == 'ar' ? const Locale('ar') : const Locale('en');
  }

  static Future<void> switchLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final currentLang = localeNotifier.value.languageCode;
    final newLang = currentLang == 'ar' ? 'en' : 'ar';
    await prefs.setString('language', newLang);
    localeNotifier.value =
        newLang == 'ar' ? const Locale('ar') : const Locale('en');
  }
}
