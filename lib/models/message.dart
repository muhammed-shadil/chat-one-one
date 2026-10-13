import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/format.dart';

enum MessageType { text, image, file, audio }

/// Emoji reactions offered on long-press.
const kReactions = ['❤️', '😂', '😮', '😢', '🙏', '👍'];

class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.type,
    this.text,
    this.url,
    this.storagePath,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.width,
    this.height,
    this.durationMs,
    this.waveform = const [],
    this.viewOnce = false,
    this.opened = false,
    this.seen = false,
    this.played = false,
    this.edited = false,
    this.reactions = const {},
    this.replyTo,
    this.createdAt,
    this.pending = false,
  });

  final String id;
  final String senderId;
  final MessageType type;

  /// Message body for text, caption for images.
  final String? text;

  /// Download URL for images, files and voice messages. Removed once a
  /// view-once photo is opened.
  final String? url;
  final String? storagePath;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final int? width;
  final int? height;

  /// Voice messages: length, and loudness bars (0–100) for the waveform.
  final int? durationMs;
  final List<int> waveform;

  final bool viewOnce;
  final bool opened;
  final bool seen;

  /// Voice messages: the receiver has listened to it.
  final bool played;
  final bool edited;

  /// Person ID (p1 / p2) to the emoji they reacted with.
  final Map<String, String> reactions;

  /// The message this one answers, if any.
  final ReplyRef? replyTo;

  /// Null while the server timestamp has not come back yet.
  final DateTime? createdAt;

  /// True until the message has reached the server.
  final bool pending;

  DateTime get time => createdAt ?? DateTime.now();

  Duration get duration => Duration(milliseconds: durationMs ?? 0);

  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final reply = d['replyTo'];
    return Message(
      id: doc.id,
      senderId: d['senderId'] as String? ?? '',
      type: MessageType.values.asNameMap()[d['type']] ?? MessageType.text,
      text: d['text'] as String?,
      url: d['url'] as String?,
      storagePath: d['storagePath'] as String?,
      fileName: d['fileName'] as String?,
      fileSize: (d['fileSize'] as num?)?.toInt(),
      mimeType: d['mimeType'] as String?,
      width: (d['width'] as num?)?.toInt(),
      height: (d['height'] as num?)?.toInt(),
      durationMs: (d['durationMs'] as num?)?.toInt(),
      waveform: [
        for (final v in d['waveform'] as List? ?? const []) (v as num).toInt(),
      ],
      viewOnce: d['viewOnce'] as bool? ?? false,
      opened: d['opened'] as bool? ?? false,
      seen: d['seen'] as bool? ?? false,
      played: d['played'] as bool? ?? false,
      edited: d['edited'] as bool? ?? false,
      reactions: {
        for (final e in (d['reactions'] as Map? ?? const {}).entries)
          if (e.value is String) e.key as String: e.value as String,
      },
      replyTo: reply is Map ? ReplyRef.fromMap(reply.cast<String, dynamic>()) : null,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      pending: doc.metadata.hasPendingWrites,
    );
  }
}

/// What a reply quotes: enough to draw the quote without loading the original.
class ReplyRef {
  const ReplyRef({
    required this.id,
    required this.senderId,
    required this.type,
    this.preview = '',
    this.viewOnce = false,
  });

  final String id;
  final String senderId;
  final MessageType type;

  /// Text, caption, file name or voice length, depending on [type].
  final String preview;
  final bool viewOnce;

  factory ReplyRef.of(Message m) => ReplyRef(
        id: m.id,
        senderId: m.senderId,
        type: m.type,
        viewOnce: m.viewOnce,
        preview: switch (m.type) {
          MessageType.text || MessageType.image => _clip(m.text ?? ''),
          MessageType.file => m.fileName ?? '',
          MessageType.audio => formatDuration(m.duration),
        },
      );

  factory ReplyRef.fromMap(Map<String, dynamic> d) => ReplyRef(
        id: d['id'] as String? ?? '',
        senderId: d['senderId'] as String? ?? '',
        type: MessageType.values.asNameMap()[d['type']] ?? MessageType.text,
        preview: d['preview'] as String? ?? '',
        viewOnce: d['viewOnce'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'senderId': senderId,
        'type': type.name,
        'preview': preview,
        if (viewOnce) 'viewOnce': true,
      };

  static String _clip(String s) => s.length <= 200 ? s : '${s.substring(0, 200)}…';
}

/// A chat member's profile and presence.
class Member {
  const Member({
    required this.id,
    this.name,
    this.online = false,
    this.typing = false,
    this.recording = false,
    this.lastSeen,
  });

  final String id;
  final String? name;
  final bool online;
  final bool typing;
  final bool recording;
  final DateTime? lastSeen;

  /// Presence is refreshed every minute while the app is open, so a stale
  /// `online` flag (app killed without going to background) expires here.
  bool get isOnline =>
      online &&
      lastSeen != null &&
      DateTime.now().difference(lastSeen!) < const Duration(minutes: 2);

  factory Member.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Member(
      id: doc.id,
      name: d['name'] as String?,
      online: d['online'] as bool? ?? false,
      typing: d['typing'] as bool? ?? false,
      recording: d['recording'] as bool? ?? false,
      lastSeen: (d['lastSeen'] as Timestamp?)?.toDate(),
    );
  }
}
