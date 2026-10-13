import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/view_once_icon.dart';

class ImageSendOptions {
  const ImageSendOptions({required this.caption, required this.viewOnce});

  final String caption;
  final bool viewOnce;
}

/// Preview a picked photo, add a caption or turn on "view once", then send.
/// Pops with [ImageSendOptions], or null if cancelled.
class ImagePreviewScreen extends StatefulWidget {
  const ImagePreviewScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  final _caption = TextEditingController();
  bool _viewOnce = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _toggleViewOnce() {
    setState(() => _viewOnce = !_viewOnce);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(_viewOnce
            ? 'Photo set to view once. It can be opened only one time.'
            : 'View once turned off.'),
      ));
  }

  void _send() => Navigator.of(context).pop(ImageSendOptions(
        caption: _viewOnce ? '' : _caption.text.trim(),
        viewOnce: _viewOnce,
      ));

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.memory(widget.bytes)),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.only(left: 16, right: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2C34),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _caption,
                              enabled: !_viewOnce,
                              minLines: 1,
                              maxLines: 4,
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: _viewOnce
                                    ? 'View once photo'
                                    : 'Add a caption…',
                                hintStyle:
                                    const TextStyle(color: Colors.white54),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'View once',
                            onPressed: _toggleViewOnce,
                            icon: ViewOnceIcon(
                              color: _viewOnce ? accent : Colors.white70,
                              filled: _viewOnce,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    tooltip: 'Send',
                    onPressed: _send,
                    shape: const CircleBorder(),
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
