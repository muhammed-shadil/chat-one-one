import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/message.dart';
import '../utils/format.dart';

/// Full-screen, zoomable photo.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({
    super.key,
    required this.message,
    required this.senderName,
  });

  final Message message;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final caption = message.text ?? '';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(senderName, style: const TextStyle(fontSize: 17)),
            Text(
              '${formatDay(message.time)}, ${formatTime(message.time)}',
              style: const TextStyle(fontSize: 12.5, color: Colors.white70),
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
                child: Hero(
                  tag: message.id,
                  child: CachedNetworkImage(
                    imageUrl: message.url ?? '',
                    fit: BoxFit.contain,
                    placeholder: (_, _) =>
                        const CircularProgressIndicator(color: Colors.white),
                    errorWidget: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 64),
                  ),
                ),
              ),
            ),
          ),
          if (caption.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ),
        ],
      ),
    );
  }
}
