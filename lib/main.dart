import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'admin_app.dart';
import 'config.dart';
import 'firebase_options.dart';
import 'screens/chat_screen.dart';
import 'screens/setup_screen.dart';
import 'services/identity.dart';
import 'services/theme_settings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On the website, real paths like /admin/photos instead of /#/admin/photos.
  // Does nothing in the phone apps.
  usePathUrlStrategy();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kUseEmulators) {
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    await FirebaseStorage.instance.useStorageEmulator('127.0.0.1', 9199);
    FirebaseFunctions.instanceFor(region: kFunctionsRegion)
        .useFunctionsEmulator('127.0.0.1', 5001);
  }
  final themeSettings = await ThemeSettings.load();
  if (kIsWeb && isAdminPath(Uri.base.path)) {
    // Instead of the chat: nobody shows as online, nothing is marked seen.
    runApp(AdminApp(themeSettings: themeSettings));
    return;
  }
  final me = await Identity.load();
  runApp(ChatApp(me: me, themeSettings: themeSettings));
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key, this.me, required this.themeSettings});

  /// Which person this phone belongs to, or null on first launch.
  final String? me;
  final ThemeSettings themeSettings;

  @override
  Widget build(BuildContext context) {
    final me = this.me;
    return ThemeSettingsScope(
      settings: themeSettings,
      child: ListenableBuilder(
        listenable: themeSettings,
        builder: (context, _) => MaterialApp(
          title: 'Chat One One',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light, themeSettings.palette),
          darkTheme: buildTheme(Brightness.dark, themeSettings.palette),
          themeMode: themeSettings.mode,
          home: me == null ? const SetupScreen() : ChatScreen(me: me),
        ),
      ),
    );
  }
}
