import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/message.dart';
import '../screens/image_viewer_screen.dart';
import '../screens/view_once_screen.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'view_once_icon.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.chat,
    required this.senderName,
    this.onLongPress,
    this.gapAbove = 2,
  });

  final Message message;
  final bool isMine;
  final ChatService chat;
  final String senderName;
  final VoidCallback? onLongPress;
  final double gapAbove;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final plainImage = m.type == MessageType.image && !m.viewOnce;
    return BubbleShell(
      isMine: isMine,
      gapAbove: gapAbove,
      onLongPress: onLongPress,
      padding: plainImage
          ? const EdgeInsets.all(3)
          : const EdgeInsets.fromLTRB(9, 6, 7, 5),
      child: switch (m.type) {
        MessageType.text => _TextContent(message: m, isMine: isMine),
        MessageType.image when m.viewOnce => _ViewOnceContent(
            message: m, isMine: isMine, chat: chat, senderName: senderName),
        MessageType.image =>
          _ImageContent(message: m, isMine: isMine, senderName: senderName),
        MessageType.file =>
          _FileContent(message: m, isMine: isMine, chat: chat),
      },
    );
  }
}

/// The rounded bubble every message (and in-progress upload) sits in.
class BubbleShell extends StatelessWidget {
  const BubbleShell({
    super.key,
    required this.isMine,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(9, 6, 7, 5),
    this.gapAbove = 2,
    this.onLongPress,
  });

  final bool isMine;
  final Widget child;
  final EdgeInsets padding;
  final double gapAbove;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return Padding(
      padding: EdgeInsets.only(top: gapAbove, left: 8, right: 8),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          child: Material(
            color: isMine ? colors.mine : colors.theirs,
            elevation: 0.6,
            shadowColor: Colors.black26,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isMine ? 12 : 3),
              topRight: Radius.circular(isMine ? 3 : 12),
              bottomLeft: const Radius.circular(12),
              bottomRight: const Radius.circular(12),
            ),
            child: InkWell(
              onLongPress: onLongPress,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Time and, for my messages, the sent / seen ticks.
class _Meta extends StatelessWidget {
  const _Meta({required this.message, required this.isMine, this.onImage = false});

  final Message message;
  final bool isMine;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final color = onImage ? Colors.white : colors.meta;
    final m = message;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatTime(m.time), style: TextStyle(fontSize: 11, color: color)),
        if (isMine) ...[
          const SizedBox(width: 3),
          Icon(
            m.pending
                ? Icons.schedule
                : m.seen
                    ? Icons.done_all
                    : Icons.done,
            size: 15,
            color: m.seen && !m.pending ? colors.seen : color,
          ),
        ],
      ],
    );
  }
}

/// Body text with the time tucked in at the end of the last line when it fits.
class _TextWithMeta extends StatelessWidget {
  const _TextWithMeta({required this.text, required this.meta});

  final String text;
  final Widget meta;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      children: [
        Text(text, style: const TextStyle(fontSize: 15.5, height: 1.3)),
        Padding(padding: const EdgeInsets.only(top: 3), child: meta),
      ],
    );
  }
}

class _TextContent extends StatelessWidget {
  const _TextContent({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) => _TextWithMeta(
        text: message.text ?? '',
        meta: _Meta(message: message, isMine: isMine),
      );
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({
    required this.message,
    required this.isMine,
    required this.senderName,
  });

  final Message message;
  final bool isMine;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final url = m.url;
    final w = m.width ?? 0, h = m.height ?? 0;
    final aspect = w > 0 && h > 0 ? (w / h).clamp(0.65, 1.6) : 1.0;
    final caption = m.text ?? '';

    return SizedBox(
      width: 250,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: AspectRatio(
              aspectRatio: aspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url == null)
                    const ColoredBox(
                        color: Colors.black12,
                        child: Icon(Icons.broken_image_outlined))
                  else
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ImageViewerScreen(
                              message: m, senderName: senderName),
                        ),
                      ),
                      child: Hero(
                        tag: m.id,
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          memCacheWidth: 600,
                          placeholder: (_, _) => const ColoredBox(
                            color: Colors.black12,
                            child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          errorWidget: (_, _, _) => const ColoredBox(
                              color: Colors.black12,
                              child: Icon(Icons.broken_image_outlined)),
                        ),
                      ),
                    ),
                  if (caption.isEmpty)
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _Meta(message: m, isMine: isMine, onImage: true),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 4, 2),
              child: _TextWithMeta(
                text: caption,
                meta: _Meta(message: m, isMine: isMine),
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewOnceContent extends StatelessWidget {
  const _ViewOnceContent({
    required this.message,
    required this.isMine,
    required this.chat,
    required this.senderName,
  });

  final Message message;
  final bool isMine;
  final ChatService chat;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final colors = ChatColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final canOpen = !isMine && !m.opened && m.url != null;
    final label = m.opened
        ? 'Opened'
        : (isMine || m.url != null)
            ? 'Photo'
            : 'Photo unavailable';

    return InkWell(
      onTap: canOpen
          ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => ViewOnceScreen(
                    message: m,
                    senderName: senderName,
                    onOpened: () => chat.markViewOnceOpened(m),
                  ),
                ),
              )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: m.opened ? 0.6 : 1,
              child: ViewOnceIcon(color: canOpen ? scheme.primary : colors.meta),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: canOpen ? FontWeight.w600 : FontWeight.normal,
                color: canOpen
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: m.opened ? 0.6 : 0.85),
              ),
            ),
            const SizedBox(width: 14),
            _Meta(message: m, isMine: isMine),
          ],
        ),
      ),
    );
  }
}

class _FileContent extends StatefulWidget {
  const _FileContent({
    required this.message,
    required this.isMine,
    required this.chat,
  });

  final Message message;
  final bool isMine;
  final ChatService chat;

  @override
  State<_FileContent> createState() => _FileContentState();
}

class _FileContentState extends State<_FileContent> {
  /// Non-null while downloading.
  double? _progress;
  bool _downloaded = false;

  @override
  void initState() {
    super.initState();
    _checkDownloaded();
  }

  Future<void> _checkDownloaded() async {
    final file = await ChatService.localFileFor(widget.message);
    if (await file.exists() && mounted) setState(() => _downloaded = true);
  }

  Future<void> _open() async {
    if (_progress != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _progress = 0);
    try {
      final file = await widget.chat.download(widget.message, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (mounted) {
        setState(() {
          _progress = null;
          _downloaded = true;
        });
      }
      final result =
          await OpenFilex.open(file.path, type: widget.message.mimeType);
      if (result.type != ResultType.done) {
        messenger.showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (e) {
      if (mounted) setState(() => _progress = null);
      widget.chat.onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final colors = ChatColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ext = fileExtension(m.fileName);
    final details = [
      if (m.fileSize != null) formatBytes(m.fileSize!),
      if (ext.isNotEmpty) ext,
    ].join(' · ');

    final Widget trailing;
    if (_progress != null) {
      trailing = Padding(
        padding: const EdgeInsets.all(4),
        child: CircularProgressIndicator(
            value: _progress == 0 ? null : _progress, strokeWidth: 2.5),
      );
    } else if (_downloaded) {
      trailing = Icon(Icons.open_in_new, size: 20, color: colors.meta);
    } else {
      trailing = Icon(Icons.download_for_offline_outlined,
          size: 28, color: colors.meta);
    }

    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Material(
            color: Colors.black.withValues(alpha: dark ? 0.18 : 0.05),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _open,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    _FileIcon(extension: ext),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.fileName ?? 'File',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w500),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(details,
                                style: TextStyle(
                                    fontSize: 12, color: colors.meta)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                        width: 32, height: 32, child: Center(child: trailing)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _Meta(message: m, isMine: widget.isMine),
        ],
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.extension});

  final String extension;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (extension.toLowerCase()) {
      'pdf' => (Icons.picture_as_pdf, Colors.red),
      'doc' || 'docx' || 'txt' || 'rtf' => (Icons.description, Colors.blue),
      'xls' || 'xlsx' || 'csv' => (Icons.table_chart, Colors.green),
      'ppt' || 'pptx' => (Icons.slideshow, Colors.deepOrange),
      'zip' || 'rar' || '7z' => (Icons.folder_zip, Colors.amber),
      'mp3' || 'wav' || 'm4a' || 'aac' || 'ogg' => (Icons.audio_file, Colors.purple),
      'mp4' || 'mov' || 'mkv' || 'avi' || '3gp' => (Icons.video_file, Colors.pink),
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' => (Icons.image, Colors.teal),
      'apk' => (Icons.android, Colors.lightGreen),
      _ => (Icons.insert_drive_file, Colors.blueGrey),
    };
    return Container(
      width: 40,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

/// Date separator between days.
class DayChip extends StatelessWidget {
  const DayChip({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: colors.chip,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1)),
            ],
          ),
          child: Text(
            formatDay(day),
            style: TextStyle(
                fontSize: 12.5, color: colors.meta, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

/// My photo or file while it is still uploading.
class UploadingBubble extends StatelessWidget {
  const UploadingBubble({
    super.key,
    required this.label,
    required this.progress,
    this.preview,
  });

  final String label;
  final ValueListenable<double> progress;
  final Uint8List? preview;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final preview = this.preview;
    return BubbleShell(
      isMine: true,
      padding: preview != null
          ? const EdgeInsets.all(3)
          : const EdgeInsets.fromLTRB(10, 9, 10, 9),
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, p, _) {
          final value = p > 0 ? p : null;
          if (preview != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: 0.55,
                      child: Image.memory(preview,
                          fit: BoxFit.cover, cacheWidth: 500),
                    ),
                    Center(
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          value: value,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return SizedBox(
            width: 250,
            child: Row(
              children: [
                Icon(Icons.upload_file, color: colors.meta),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: value),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
