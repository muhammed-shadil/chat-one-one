import 'dart:async';

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../services/chat_service.dart';
import '../utils/format.dart';

/// App bar title: the other person's name and online / typing / last seen.
class PresenceTitle extends StatefulWidget {
  const PresenceTitle({super.key, required this.chat});

  final ChatService chat;

  @override
  State<PresenceTitle> createState() => _PresenceTitleState();
}

class _PresenceTitleState extends State<PresenceTitle> {
  late final Stream<Member> _other = widget.chat.watchMember(widget.chat.other);
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // "online" expires by time, so re-evaluate it even without new data.
    _tick = Timer.periodic(
        const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Member>(
      stream: _other,
      builder: (context, snap) {
        final member = snap.data;
        final name = member?.name ?? 'Waiting for them to join';
        final status = switch (member) {
          null => '',
          Member(isOnline: true, recording: true) => 'recording audio…',
          Member(isOnline: true, typing: true) => 'typing…',
          Member(isOnline: true) => 'online',
          Member(:final lastSeen?) => formatLastSeen(lastSeen),
          _ => '',
        };
        final fg = Theme.of(context).appBarTheme.foregroundColor;
        return Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: Colors.white24,
              foregroundColor: fg,
              child: Text(
                (member?.name?.trim().isNotEmpty ?? false)
                    ? member!.name!.trim()[0].toUpperCase()
                    : '?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                  if (status.isNotEmpty)
                    Text(status,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: fg?.withValues(alpha: 0.8))),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
