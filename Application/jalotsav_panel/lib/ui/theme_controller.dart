import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light / dark / follow-the-system choice, remembered across launches.
class ThemeController extends ChangeNotifier {
  ThemeController([this._mode = ThemeMode.system]);

  static const _key = 'theme_mode';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  /// Reads the saved choice. Falls back to [ThemeMode.system] if there is
  /// none, or if storage is unavailable.
  static Future<ThemeController> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      return ThemeController(mode ?? ThemeMode.system);
    } on Object catch (e) {
      debugPrint('[theme] could not read saved theme: $e');
      return ThemeController();
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } on Object catch (e) {
      debugPrint('[theme] could not save theme: $e');
    }
  }

  /// The one-tap toggle in the status bar: flips whatever is on screen now.
  Future<void> toggle(Brightness current) =>
      setMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}
