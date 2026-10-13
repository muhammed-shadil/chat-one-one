import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A photo from Firebase Storage.
///
/// On phones it goes through the disk cache. In the browser it uses
/// [Image.network], which falls back to an `<img>` element when the Storage
/// bucket has no CORS policy, so photos show without any bucket setup.
class NetworkPhoto extends StatelessWidget {
  const NetworkPhoto({
    super.key,
    required this.url,
    required this.placeholder,
    required this.error,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String url;
  final Widget placeholder;
  final Widget error;
  final BoxFit fit;

  /// Width to decode at on phones, to keep thumbnails light on memory.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        memCacheWidth: cacheWidth,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => error,
      );
    }
    return Image.network(
      url,
      fit: fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder,
      errorBuilder: (_, _, _) => error,
    );
  }
}
