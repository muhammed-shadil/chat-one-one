import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/admin_photos_screen.dart';
import 'services/admin_service.dart';
import 'services/theme_settings.dart';
import 'theme.dart';

/// Whether the website was opened on the admin page (`/admin/photos`, or
/// just `/admin`) instead of the chat.
bool isAdminPath(String path) => path == '/admin' || path.startsWith('/admin/');

/// The website's admin page. It runs instead of the chat, so opening it
/// never shows anyone as online or marks messages as seen.
class AdminApp extends StatelessWidget {
  const AdminApp({super.key, required this.themeSettings, this.loadPhotos});

  final ThemeSettings themeSettings;

  /// Defaults to the `adminPhotos` Cloud Function; tests pass their own.
  final PhotoLoader? loadPhotos;

  @override
  Widget build(BuildContext context) {
    final load = loadPhotos ?? AdminService().listPhotos;
    // Named, so the address bar keeps showing /admin/photos.
    Route<void> photos() => MaterialPageRoute(
          settings: const RouteSettings(name: kAdminPhotosPath),
          builder: (_) => AdminPhotosScreen(loadPhotos: load),
        );
    return MaterialApp(
      title: 'Photos · Admin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, themeSettings.palette),
      darkTheme: buildTheme(Brightness.dark, themeSettings.palette),
      themeMode: themeSettings.mode,
      onGenerateInitialRoutes: (_) => [photos()],
      onGenerateRoute: (_) => photos(),
    );
  }
}
