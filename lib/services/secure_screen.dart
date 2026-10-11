import 'package:flutter/services.dart';

/// Blocks screenshots and screen recording while a view-once photo is shown.
/// Implemented on Android (FLAG_SECURE in MainActivity); a no-op elsewhere.
class SecureScreen {
  static const _channel = MethodChannel('chat_one_one/secure_screen');

  static Future<void> enable() => _invoke('enable');
  static Future<void> disable() => _invoke('disable');

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Not supported on this platform.
    } on PlatformException {
      // Ignore; the photo is still shown.
    }
  }
}
