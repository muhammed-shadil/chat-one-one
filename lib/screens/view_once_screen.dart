import 'package:flutter/material.dart';

import '../models/message.dart';
import '../services/secure_screen.dart';
import '../widgets/view_once_icon.dart';

/// Shows a view-once photo a single time.
///
/// The photo is fetched straight into memory (never the disk cache). As soon
/// as it is on screen, [onOpened] marks it opened, which moves it out of the
/// chat into the private archive; when this screen closes it is dropped from
/// memory too.
/// Screenshots are blocked on Android while this screen is open.
class ViewOnceScreen extends StatefulWidget {
  const ViewOnceScreen({
    super.key,
    required this.message,
    required this.senderName,
    required this.onOpened,
  });

  final Message message;
  final String senderName;
  final Future<void> Function() onOpened;

  @override
  State<ViewOnceScreen> createState() => _ViewOnceScreenState();
}

class _ViewOnceScreenState extends State<ViewOnceScreen> {
  // In the browser, falls back to an <img> element if Storage blocks CORS.
  late final NetworkImage _image = NetworkImage(widget.message.url!,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback);
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    SecureScreen.enable();
  }

  @override
  void dispose() {
    SecureScreen.disable();
    _image.evict();
    super.dispose();
  }

  void _shown() {
    if (_reported) return;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onOpened());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const ViewOnceIcon(color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.senderName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image(
                  image: _image,
                  fit: BoxFit.contain,
                  frameBuilder: (context, child, frame, _) {
                    if (frame != null) _shown();
                    return child;
                  },
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    final total = progress.expectedTotalBytes;
                    return CircularProgressIndicator(
                      color: Colors.white,
                      value: total == null
                          ? null
                          : progress.cumulativeBytesLoaded / total,
                    );
                  },
                  errorBuilder: (context, _, _) => const Text(
                    'This photo could not be loaded.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
          const SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'View once photo — it disappears after you close it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
