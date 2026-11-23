import '../config.dart';

/// Where a photo is now, as listed by the `adminPhotos` Cloud Function.
enum PhotoStatus {
  chat('In chat'),
  viewOnce('View once, not opened'),
  opened('View once, opened'),
  deleted('Deleted'),
  unlinked('Storage only');

  const PhotoStatus(this.label);

  final String label;

  static PhotoStatus parse(Object? value) => switch (value) {
        'chat' => chat,
        'view_once' => viewOnce,
        'opened' => opened,
        'deleted' => deleted,
        _ => unlinked,
      };
}

/// One photo on the admin page: from the chat, the archive, or Storage.
class AdminPhoto {
  const AdminPhoto({
    required this.key,
    required this.chatId,
    required this.status,
    this.messageId,
    this.senderId,
    this.viewOnce = false,
    this.caption,
    this.fileName,
    this.sentAt,
    this.openedAt,
    this.deletedAt,
    this.width,
    this.height,
    this.size,
    this.path,
    this.url,
  });

  final String key;
  final String chatId;
  final PhotoStatus status;
  final String? messageId;

  /// p1 or p2; null for a file no message points to.
  final String? senderId;
  final bool viewOnce;
  final String? caption;

  /// For photos sent as a file.
  final String? fileName;

  /// When it was sent, or uploaded for [PhotoStatus.unlinked].
  final DateTime? sentAt;
  final DateTime? openedAt;
  final DateTime? deletedAt;
  final int? width;
  final int? height;

  /// Bytes in Storage; null when the file is gone.
  final int? size;

  /// Where it is in Storage.
  final String? path;

  /// Signed link that works for an hour or two; null when the file is gone.
  final String? url;

  factory AdminPhoto.fromMap(Map<String, dynamic> d) => AdminPhoto(
        key: d['key'] as String,
        chatId: d['chatId'] as String? ?? '',
        status: PhotoStatus.parse(d['status']),
        messageId: d['messageId'] as String?,
        senderId: d['senderId'] as String?,
        viewOnce: d['viewOnce'] == true,
        caption: d['caption'] as String?,
        fileName: d['fileName'] as String?,
        sentAt: _time(d['sentAt']),
        openedAt: _time(d['openedAt']),
        deletedAt: _time(d['deletedAt']),
        width: (d['width'] as num?)?.toInt(),
        height: (d['height'] as num?)?.toInt(),
        size: (d['size'] as num?)?.toInt(),
        path: d['path'] as String?,
        url: d['url'] as String?,
      );
}

/// A chat ID found in the database, with the names its two people chose.
class AdminChat {
  const AdminChat({required this.id, this.names = const {}, this.photoCount = 0});

  final String id;
  final Map<String, String> names;
  final int photoCount;

  /// The chat the app uses (as opposed to one left over from an old ID).
  bool get isCurrent => id == kChatId;

  factory AdminChat.fromMap(Map<String, dynamic> d) => AdminChat(
        id: d['id'] as String,
        names: {
          for (final e in _map(d['names']).entries)
            if (e.value is String) e.key: e.value as String,
        },
        photoCount: (d['photoCount'] as num?)?.toInt() ?? 0,
      );
}

/// Everything the admin page shows.
class AdminPhotoList {
  const AdminPhotoList({
    required this.chats,
    required this.photos,
    required this.linksExpireAt,
  });

  final List<AdminChat> chats;

  /// Newest first.
  final List<AdminPhoto> photos;

  /// When the photos' links stop working.
  final DateTime linksExpireAt;

  /// The display name of [senderId] in [chatId].
  String nameOf(String chatId, String? senderId) {
    if (senderId == null) return 'Unknown';
    for (final chat in chats) {
      if (chat.id == chatId && chat.names[senderId] != null) {
        return chat.names[senderId]!;
      }
    }
    return switch (senderId) {
      kPerson1 => 'Person 1',
      kPerson2 => 'Person 2',
      _ => senderId,
    };
  }

  /// Parses the callable's result. On the web it arrives as nested
  /// `Map<Object?, Object?>`s, hence the conversions.
  factory AdminPhotoList.fromData(Object? data) {
    final d = _map(data);
    return AdminPhotoList(
      chats: [for (final c in d['chats'] as List? ?? const []) AdminChat.fromMap(_map(c))],
      photos: [for (final p in d['photos'] as List? ?? const []) AdminPhoto.fromMap(_map(p))],
      linksExpireAt: _time(d['linksExpireAt']) ?? DateTime.now(),
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.map((k, v) => MapEntry(k.toString(), v)) : const {};

DateTime? _time(Object? ms) =>
    ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
