import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'firebase_options.dart';
import 'screens/chat_screen.dart';
import 'screens/setup_screen.dart';
import 'services/identity.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kUseEmulators) {
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    await FirebaseStorage.instance.useStorageEmulator('127.0.0.1', 9199);
  }
  final me = await Identity.load();
  runApp(ChatApp(me: me));
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key, this.me});

  /// Which person this phone belongs to, or null on first launch.
  final String? me;

  @override
  Widget build(BuildContext context) {
    final me = this.me;
    return MaterialApp(
      title: 'Chat One One',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: me == null ? const SetupScreen() : ChatScreen(me: me),
    );
  }
}
