import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeService {
  ThemeModeService._();

  static const String _key = 'foxy.theme_mode.v1';
  static final ValueNotifier<ThemeMode> notifier = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  static Future<void> init() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? value = prefs.getString(_key);
    notifier.value = _fromStorage(value);
  }

  static ThemeMode get mode => notifier.value;

  static bool get isDarkActive {
    final ThemeMode value = notifier.value;
    if (value == ThemeMode.dark) {
      return true;
    }
    if (value == ThemeMode.light) {
      return false;
    }
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  static Future<void> setMode(ThemeMode mode) async {
    if (notifier.value == mode) {
      return;
    }
    notifier.value = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  static ThemeMode _fromStorage(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
