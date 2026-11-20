import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jalotsav_panel/ui/theme_controller.dart';

void main() {
  test('follows the system when nothing is saved', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await ThemeController.load()).mode, ThemeMode.system);
  });

  test('restores the saved choice', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    expect((await ThemeController.load()).mode, ThemeMode.light);
  });

  test('ignores an unknown saved value', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});
    expect((await ThemeController.load()).mode, ThemeMode.system);
  });

  test('a new choice notifies and survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController();
    var notified = 0;
    theme.addListener(() => notified++);

    await theme.setMode(ThemeMode.dark);

    expect(theme.mode, ThemeMode.dark);
    expect(notified, 1);
    expect((await ThemeController.load()).mode, ThemeMode.dark);
  });

  test('toggle flips what is on screen', () async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController();
    await theme.toggle(Brightness.dark);
    expect(theme.mode, ThemeMode.light);
    await theme.toggle(Brightness.light);
    expect(theme.mode, ThemeMode.dark);
  });
}
