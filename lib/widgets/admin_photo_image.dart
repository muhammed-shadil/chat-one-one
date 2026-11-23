import 'package:flutter/material.dart';

import '../models/admin_photo.dart';
import 'view_once_icon.dart';

/// A photo on the admin page, loaded through its signed link.
///
/// The `adminPhoto` function allows any origin, so the browser draws it like
/// any other image (and [cacheWidth] keeps thumbnails light). If that ever
/// fails, it falls back to an `<img>` element.
class AdminPhotoImage extends StatelessWidget {
  const AdminPhotoImage({
    super.key,
    required this.photo,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.dark = false,
  });

  final AdminPhoto photo;
  final BoxFit fit;
  final int? cacheWidth;

  /// Light-on-black placeholders, for the full-screen viewer.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final url = photo.url;
    final muted = dark ? Colors.white54 : Theme.of(context).colorScheme.onSurfaceVariant;
    if (url == null) {
      return _Problem(icon: Icons.hide_image_outlined, text: 'File missing', color: muted);
    }
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: muted),
              ),
            ),
      errorBuilder: (_, _, _) =>
          _Problem(icon: Icons.broken_image_outlined, text: "Couldn't load", color: muted),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 4),
            Text(text, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      );
}

/// "View once", "Opened", "Deleted" or "Storage only", over a photo.
class PhotoStatusBadge extends StatelessWidget {
  const PhotoStatusBadge({super.key, required this.photo});

  final AdminPhoto photo;

  @override
  Widget build(BuildContext context) {
    const color = Colors.white;
    final (Widget icon, String text) = switch (photo.status) {
      PhotoStatus.viewOnce => (const ViewOnceIcon(color: color, size: 14), 'Not opened'),
      PhotoStatus.opened => (const ViewOnceIcon(color: color, size: 14, filled: true), 'Opened'),
      PhotoStatus.deleted => (const Icon(Icons.delete_outline, color: color, size: 15), 'Deleted'),
      PhotoStatus.unlinked => (const Icon(Icons.cloud_outlined, color: color, size: 15), 'Storage only'),
      PhotoStatus.chat => (const ViewOnceIcon(color: color, size: 14), 'View once'),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: switch (photo.status) {
          PhotoStatus.deleted => const Color(0xD0B3261E),
          PhotoStatus.opened => const Color(0xD07A4F01),
          _ => const Color(0xB3000000),
        },
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                // A deleted photo that was also view once says so.
                photo.status == PhotoStatus.deleted && photo.viewOnce
                    ? 'Deleted · view once'
                    : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
