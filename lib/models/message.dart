import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, file }

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
    this.viewOnce = false,
    this.opened = false,
    this.seen = false,
    this.createdAt,
    this.pending = false,
  });

  final String id;
  final String senderId;
  final MessageType type;

  /// Message body for text, caption for images.
  final String? text;

  /// Download URL for images and files. Removed once a view-once photo is opened.
  final String? url;
  final String? storagePath;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final int? width;
  final int? height;

  final bool viewOnce;
  final bool opened;
  final bool seen;

  /// Null while the server timestamp has not come back yet.
  final DateTime? createdAt;

  /// True until the message has reached the server.
  final bool pending;

  DateTime get time => createdAt ?? DateTime.now();

  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
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
      viewOnce: d['viewOnce'] as bool? ?? false,
      opened: d['opened'] as bool? ?? false,
      seen: d['seen'] as bool? ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      pending: doc.metadata.hasPendingWrites,
    );
  }
}

/// A chat member's profile and presence.
class Member {
  const Member({
    required this.id,
    this.name,
    this.online = false,
    this.typing = false,
    this.lastSeen,
  });

  final String id;
  final String? name;
  final bool online;
  final bool typing;
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
      lastSeen: (d['lastSeen'] as Timestamp?)?.toDate(),
    );
  }
}
