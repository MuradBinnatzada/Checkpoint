import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the app looks on this device (Settings > Appearance): the theme, which
/// follows the device's light or dark setting until the member picks one, and
/// the accessibility switches, Increase contrast and Reduce motion. The device's
/// own accessibility settings turn those on too (see CheckpointApp); these are
/// for asking the app alone.
///
/// It is the device's choice, not the account's, so it stays through a sign-out
/// and is not one of [AppStores]: main.dart reads it before the first frame, so
/// the app never opens in the other theme and flips.
class AppearanceStore extends ChangeNotifier {
  AppearanceStore({
    this._themeMode = ThemeMode.system,
    this._highContrast = false,
    this._reduceMotion = false,
  });

  static const _themeModeKey = 'theme_mode';
  static const _highContrastKey = 'high_contrast';
  static const _reduceMotionKey = 'reduce_motion';

  /// The store with the choices saved on this device. Never throws: a choice
  /// that can't be read is no choice.
  static Future<AppearanceStore> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = ThemeMode.values
          .asNameMap()[prefs.getString(_themeModeKey)];
      return AppearanceStore(
        themeMode: saved ?? ThemeMode.system,
        highContrast: prefs.getBool(_highContrastKey) ?? false,
        reduceMotion: prefs.getBool(_reduceMotionKey) ?? false,
      );
    } catch (e) {
      debugPrint('Reading the appearance failed: $e');
      return AppearanceStore();
    }
  }

  ThemeMode _themeMode;

  /// System (the device's setting), light or dark.
  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _save((prefs) => prefs.setString(_themeModeKey, mode.name));
  }

  bool _highContrast;

  /// Stronger text, colors and borders: the high contrast themes.
  bool get highContrast => _highContrast;

  Future<void> setHighContrast(bool on) async {
    if (on == _highContrast) return;
    _highContrast = on;
    notifyListeners();
    await _save((prefs) => prefs.setBool(_highContrastKey, on));
  }

  bool _reduceMotion;

  /// Pages fade instead of sliding, and nothing animates just for show.
  bool get reduceMotion => _reduceMotion;

  Future<void> setReduceMotion(bool on) async {
    if (on == _reduceMotion) return;
    _reduceMotion = on;
    notifyListeners();
    await _save((prefs) => prefs.setBool(_reduceMotionKey, on));
  }

  static Future<void> _save(
    Future<bool> Function(SharedPreferences prefs) write,
  ) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('Saving the appearance failed: $e');
    }
  }
}
