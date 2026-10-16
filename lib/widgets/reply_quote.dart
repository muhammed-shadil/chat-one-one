import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme.dart';

/// A boxed quote with a colored bar: the message a reply answers, shown in the
/// reply's bubble and above the input while writing it.
class QuoteBox extends StatelessWidget {
  const QuoteBox({
    super.key,
    required this.title,
    required this.text,
    required this.accent,
    this.icon,
    this.onTap,
    this.onClose,
    this.closeTooltip = 'Cancel',
  });

  final String title;
  final String text;
  final Color accent;
  final IconData? icon;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.black.withValues(alpha: dark ? 0.2 : 0.05),
      borderRadius: BorderRadius.circular(7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 15, color: colors.meta),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: colors.meta, fontSize: 13.5)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: closeTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: Icon(Icons.close, size: 20, color: colors.meta),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The quote for [reply]: who wrote it and what it was.
class ReplyQuote extends StatelessWidget {
  const ReplyQuote({
    super.key,
    required this.reply,
    required this.name,
    required this.fromMe,
    this.onTap,
    this.onClose,
  });

  final ReplyRef reply;

  /// "You" or the other person's name.
  final String name;
  final bool fromMe;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = describe(reply);
    return QuoteBox(
      title: name,
      text: text,
      icon: icon,
      accent: fromMe
          ? ChatColors.of(context).myAccent
          : ChatColors.of(context).otherAccent,
      onTap: onTap,
      onClose: onClose,
      closeTooltip: 'Cancel reply',
    );
  }

  /// An icon (if any) and a line of text standing in for the quoted message.
  static (IconData?, String) describe(ReplyRef r) => switch (r.type) {
        MessageType.text => (null, r.preview),
        MessageType.image when r.viewOnce => (Icons.looks_one_outlined, 'View once photo'),
        MessageType.image => (Icons.photo, r.preview.isEmpty ? 'Photo' : r.preview),
        MessageType.file => (Icons.insert_drive_file, r.preview.isEmpty ? 'File' : r.preview),
        MessageType.audio => (Icons.mic, 'Voice message (${r.preview})'),
      };
}
