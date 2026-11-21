import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService instance = ThemeService._internal();
  ThemeService._internal();

  static const String _prefKey = 'lichat_theme_mode';
  ThemeMode _currentMode = ThemeMode.system;

  ThemeMode get currentMode => _currentMode;

  bool get isDarkMode {
    if (_currentMode == ThemeMode.dark) return true;
    if (_currentMode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey) ?? 'system';
      if (saved == 'dark') {
        _currentMode = ThemeMode.dark;
      } else if (saved == 'light') {
        _currentMode = ThemeMode.light;
      } else {
        _currentMode = ThemeMode.system;
      }
    } catch (e) {
      _currentMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_currentMode == mode) return;
    _currentMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      String val = 'system';
      if (mode == ThemeMode.dark) val = 'dark';
      if (mode == ThemeMode.light) val = 'light';
      await prefs.setString(_prefKey, val);
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    await setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }

  static Future<void> toggle() => instance.toggleTheme();
}
