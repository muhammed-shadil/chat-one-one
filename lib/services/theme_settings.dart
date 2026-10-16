import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// The color theme and light / dark choice, remembered on this device.
/// Each phone or browser picks its own; the other person isn't affected.
class ThemeSettings extends ChangeNotifier {
  ThemeSettings._(this._prefs, this._palette, this._mode);

  static const _paletteKey = 'theme.palette';
  static const _modeKey = 'theme.mode';

  static Future<ThemeSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ThemeSettings._(
      prefs,
      paletteById(prefs.getString(_paletteKey)),
      ThemeMode.values.asNameMap()[prefs.getString(_modeKey)] ?? ThemeMode.system,
    );
  }

  /// The settings provided above [context] by [ThemeSettingsScope].
  static ThemeSettings of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ThemeSettingsScope>()!
      .notifier!;

  final SharedPreferences _prefs;
  ChatPalette _palette;
  ThemeMode _mode;

  ChatPalette get palette => _palette;
  ThemeMode get mode => _mode;

  set palette(ChatPalette value) {
    if (value == _palette) return;
    _palette = value;
    notifyListeners();
    _prefs.setString(_paletteKey, value.id);
  }

  set mode(ThemeMode value) {
    if (value == _mode) return;
    _mode = value;
    notifyListeners();
    _prefs.setString(_modeKey, value.name);
  }
}

/// Makes [ThemeSettings] available below it and rebuilds dependents when the
/// theme changes.
class ThemeSettingsScope extends InheritedNotifier<ThemeSettings> {
  const ThemeSettingsScope({
    super.key,
    required ThemeSettings settings,
    required super.child,
  }) : super(notifier: settings);
}
