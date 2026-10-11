import 'package:shared_preferences/shared_preferences.dart';

/// Remembers on this phone which of the two people is using it.
/// This replaces login: it is picked once on first launch.
class Identity {
  static const _key = 'me';

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> save(String personId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, personId);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
