import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'chat_service.dart';

/// Push notifications for new messages while the app or website is closed.
/// The `notifyNewMessage` Cloud Function sends them to the tokens saved here.
class Push {
  static StreamSubscription<String>? _refresh;

  /// Asks for permission (the system only asks once) and registers this
  /// phone or browser to be notified for [personId].
  static Future<void> register(String personId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      if (!await messaging.isSupported()) return;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();
      if (token != null) await ChatService.addPushToken(personId, token);
      await _refresh?.cancel();
      _refresh = messaging.onTokenRefresh
          .listen((t) => ChatService.addPushToken(personId, t).ignore());
    } catch (e) {
      // Notifications are a bonus; the chat works without them.
      debugPrint('Push notifications unavailable: $e');
    }
  }

  /// Stops notifications here for [personId], e.g. when switching person.
  static Future<void> unregister(String personId) async {
    try {
      await _refresh?.cancel();
      _refresh = null;
      final messaging = FirebaseMessaging.instance;
      if (!await messaging.isSupported()) return;
      final token = await messaging.getToken();
      if (token != null) await ChatService.removePushToken(personId, token);
      await messaging.deleteToken();
    } catch (e) {
      debugPrint('Could not turn off push notifications: $e');
    }
  }
}
