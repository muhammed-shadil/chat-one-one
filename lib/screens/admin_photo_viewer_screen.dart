import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/admin_photo.dart';
import '../utils/format.dart';
import '../widgets/admin_photo_image.dart';

/// Full-screen, zoomable photos from the admin page. Swipe, or use the
/// arrow buttons or keys, to go through them; Escape closes.
class AdminPhotoViewerScreen extends StatefulWidget {
  const AdminPhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.nameOf,
  });

  final List<AdminPhoto> photos;
  final int initialIndex;
  final String Function(AdminPhoto photo) nameOf;

  @override
  State<AdminPhotoViewerScreen> createState() => _AdminPhotoViewerScreenState();
}

class _AdminPhotoViewerScreenState extends State<AdminPhotoViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _showDetails = true;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.photos.length) return;
    _pages.animateToPage(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    final count = widget.photos.length;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.nameOf(photo), style: const TextStyle(fontSize: 17)),
                Text('${_index + 1} of $count',
                    style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: _showDetails ? 'Hide details' : 'Show details',
                icon: Icon(_showDetails ? Icons.info : Icons.info_outline),
                onPressed: () => setState(() => _showDetails = !_showDetails),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pages,
                      itemCount: count,
                      // Also loads the photos either side, so swiping is instant.
                      allowImplicitScrolling: true,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (_, i) => InteractiveViewer(
                        maxScale: 6,
                        child: Center(
                          child: AdminPhotoImage(
                            photo: widget.photos[i],
                            fit: BoxFit.contain,
                            dark: true,
                          ),
                        ),
                      ),
                    ),
                    if (_index > 0)
                      _Arrow(
                        alignment: Alignment.centerLeft,
                        icon: Icons.chevron_left,
                        tooltip: 'Previous',
                        onPressed: () => _go(-1),
                      ),
                    if (_index < count - 1)
                      _Arrow(
                        alignment: Alignment.centerRight,
                        icon: Icons.chevron_right,
                        tooltip: 'Next',
                        onPressed: () => _go(1),
                      ),
                  ],
                ),
              ),
              if (_showDetails) _Details(photo: photo),
            ],
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: IconButton.filled(
            tooltip: tooltip,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
            ),
            icon: Icon(icon, size: 28),
            onPressed: onPressed,
          ),
        ),
      );
}

/// When it was sent, opened or deleted, its caption, and where it's stored.
class _Details extends StatelessWidget {
  const _Details({required this.photo});

  final AdminPhoto photo;

  static String _when(DateTime t) => '${formatDay(t)}, ${formatTime(t)}';

  @override
  Widget build(BuildContext context) {
    const secondary = TextStyle(color: Colors.white70, fontSize: 13);
    final sentAt = photo.sentAt, openedAt = photo.openedAt, deletedAt = photo.deletedAt;
    final size = photo.size, width = photo.width, height = photo.height;
    final caption = photo.caption;
    final facts = [
      if (width != null && height != null) '$width × $height',
      if (size != null) formatBytes(size),
      ?photo.fileName,
    ];
    return ColoredBox(
      color: const Color(0xFF161616),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (photo.status != PhotoStatus.chat || photo.viewOnce)
                      PhotoStatusBadge(photo: photo)
                    else
                      const Text('In chat', style: TextStyle(color: Colors.white)),
                    if (sentAt != null)
                      Text(
                        '${photo.status == PhotoStatus.unlinked ? 'Uploaded' : 'Sent'} ${_when(sentAt)}',
                        style: secondary,
                      ),
                    if (openedAt != null) Text('Opened ${_when(openedAt)}', style: secondary),
                    if (deletedAt != null) Text('Deleted ${_when(deletedAt)}', style: secondary),
                  ],
                ),
                if (caption != null) ...[
                  const SizedBox(height: 8),
                  Text(caption, style: const TextStyle(color: Colors.white, fontSize: 15)),
                ],
                const SizedBox(height: 8),
                SelectableText(
                  [...facts, ?photo.path].join('  ·  '),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
