import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/feature_flags.dart';

/// Decides whether the surprise screen opens by itself when the app starts
/// (see [FeatureFlags]). This only controls showing the screen: nothing is
/// shared unless the person taps "Share My Location" on it.
class SurprisePrompt {
  SurprisePrompt._();

  static String _shownKey(String personId) => 'surprise.shown.$personId';

  static bool shouldShow({
    required bool enabled,
    required bool everyOpen,
    required bool alreadyShown,
  }) =>
      enabled && (everyOpen || !alreadyShown);

  /// True if it should open now for [personId]. When it opens only once,
  /// this also remembers that it has (per person, so switching person on the
  /// same phone shows it to the other one too).
  static Future<bool> takeTurn(
    String personId, {
    bool enabled = FeatureFlags.enableSurpriseLocation,
    bool everyOpen = FeatureFlags.showOnEveryAppOpen,
  }) async {
    if (!enabled) return false;
    if (everyOpen) return true;
    final prefs = await SharedPreferences.getInstance();
    final key = _shownKey(personId);
    final show = shouldShow(
      enabled: enabled,
      everyOpen: everyOpen,
      alreadyShown: prefs.getBool(key) ?? false,
    );
    if (show) await prefs.setBool(key, true);
    return show;
  }
}
