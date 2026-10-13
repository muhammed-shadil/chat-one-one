import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/message.dart';

typedef ProgressCallback = void Function(double progress);

/// Firestore layout:
///   chats/{kChatId}/messages/{messageId}
///   chats/{kChatId}/members/{p1|p2}   name + presence
///   chats/{kChatId}/deleted/{messageId}   archive, written by Cloud Functions
/// Storage layout:
///   chats/{kChatId}/images/{messageId}.{ext}
///   chats/{kChatId}/files/{messageId}/{fileName}
///   chats/{kChatId}/audio/{messageId}.{m4a|webm}   voice messages
///   chats/{kChatId}/deleted/{messageId}/{name}   archive, Cloud Functions only
class ChatService {
  ChatService(this.me, {required this.onError});

  final String me;
  String get other => otherPerson(me);

  /// Called when a background write fails (e.g. rules rejected it).
  final void Function(Object error) onError;

  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  static DocumentReference<Map<String, dynamic>> get _chat =>
      _db.collection('chats').doc(kChatId);
  static CollectionReference<Map<String, dynamic>> get _messages =>
      _chat.collection('messages');
  static CollectionReference<Map<String, dynamic>> get _members =>
      _chat.collection('members');

  // ---------------------------------------------------------------- members

  static Future<Map<String, Member>> fetchMembers() async {
    final snap = await _members.get();
    return {for (final d in snap.docs) d.id: Member.fromDoc(d)};
  }

  /// Firestore applies writes locally at once and syncs when online, so the
  /// returned future is only for error reporting; callers need not await it.
  static Future<void> saveName(String personId, String name) =>
      _members.doc(personId).set({'name': name}, SetOptions(merge: true));

  Stream<Member> watchMember(String personId) =>
      _members.doc(personId).snapshots().map(Member.fromDoc);

  void setOnline(bool online) => _members.doc(me).set({
        'online': online,
        'lastSeen': FieldValue.serverTimestamp(),
        if (!online) 'typing': false,
      }, SetOptions(merge: true)).ignore();

  void setTyping(bool typing) => _members
      .doc(me)
      .set({'typing': typing}, SetOptions(merge: true)).ignore();

  /// Shows "recording audio…" to the other person.
  void setRecording(bool recording) => _members
      .doc(me)
      .set({'recording': recording}, SetOptions(merge: true)).ignore();

  /// Push notification tokens, one per phone or browser this person uses.
  /// The `notifyNewMessage` Cloud Function sends to them.
  static Future<void> addPushToken(String personId, String token) =>
      _members.doc(personId).set({
        'pushTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

  static Future<void> removePushToken(String personId, String token) =>
      _members.doc(personId).set({
        'pushTokens': FieldValue.arrayRemove([token]),
      }, SetOptions(merge: true));

  // --------------------------------------------------------------- messages

  /// Newest first.
  Stream<List<Message>> watchMessages(int limit) => _messages
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Message.fromDoc).toList());

  void sendText(String text, {ReplyRef? replyTo}) => _write(_messages.add({
        ..._base(MessageType.text, replyTo),
        'text': text,
      }));

  /// Changes the text of one of my messages. The `archiveEditedMessage`
  /// Cloud Function keeps the previous version in the archive.
  void editText(Message m, String text) => _write(_messages.doc(m.id).update({
        'text': text,
        'edited': true,
        'editedAt': FieldValue.serverTimestamp(),
      }));

  /// Sets my reaction to [m], or removes it when [emoji] is null.
  void react(Message m, String? emoji) => _write(_messages.doc(m.id).update({
        'reactions.$me': emoji ?? FieldValue.delete(),
      }));

  /// Called when I play a voice message the other person sent.
  void markPlayed(Message m) {
    if (m.senderId == other && !m.played) {
      _write(_messages.doc(m.id).update({'played': true}));
    }
  }

  Future<void> sendImage({
    required Uint8List bytes,
    required String name,
    required int width,
    required int height,
    String? caption,
    bool viewOnce = false,
    ReplyRef? replyTo,
    ProgressCallback? onProgress,
  }) async {
    final doc = _messages.doc();
    final mimeType = lookupMimeType(name, headerBytes: bytes) ?? 'image/jpeg';
    final path = 'chats/$kChatId/images/${doc.id}.${_extension(name, 'jpg')}';
    final url = await _upload(path,
        bytes: bytes, mimeType: mimeType, onProgress: onProgress);
    _write(doc.set({
      ..._base(MessageType.image, replyTo),
      if (caption != null && caption.isNotEmpty) 'text': caption,
      'url': url,
      'storagePath': path,
      'mimeType': mimeType,
      'width': width,
      'height': height,
      'viewOnce': viewOnce,
      'opened': false,
    }));
  }

  Future<void> sendAudio({
    required Uint8List bytes,
    required String mimeType,
    required String extension,
    required Duration duration,
    required List<int> waveform,
    ReplyRef? replyTo,
    ProgressCallback? onProgress,
  }) async {
    final doc = _messages.doc();
    final path = 'chats/$kChatId/audio/${doc.id}.$extension';
    final url = await _upload(path,
        bytes: bytes, mimeType: mimeType, onProgress: onProgress);
    _write(doc.set({
      ..._base(MessageType.audio, replyTo),
      'url': url,
      'storagePath': path,
      'mimeType': mimeType,
      'fileSize': bytes.length,
      'durationMs': duration.inMilliseconds,
      'waveform': waveform,
      'played': false,
    }));
  }

  Future<void> sendFile(
    PlatformFile picked, {
    required int size,
    ReplyRef? replyTo,
    ProgressCallback? onProgress,
  }) async {
    final doc = _messages.doc();
    final mimeType = lookupMimeType(picked.name) ?? 'application/octet-stream';
    final path = 'chats/$kChatId/files/${doc.id}/${_safeName(picked.name)}';
    final localPath = picked.path;
    final url = await _upload(
      path,
      file: localPath != null ? File(localPath) : null,
      bytes: localPath == null ? await picked.readAsBytes() : null,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    _write(doc.set({
      ..._base(MessageType.file, replyTo),
      'url': url,
      'storagePath': path,
      'fileName': picked.name,
      'fileSize': size,
      'mimeType': mimeType,
    }));
  }

  /// Marks the other person's messages as read.
  void markSeen(Iterable<Message> messages) {
    final unseen =
        messages.where((m) => m.senderId == other && !m.seen).toList();
    if (unseen.isEmpty) return;
    final batch = _db.batch();
    for (final m in unseen) {
      batch.update(_messages.doc(m.id), {'seen': true});
    }
    _write(batch.commit());
  }

  /// Called by the receiver once a view-once photo is on screen: its link is
  /// removed so it can't be opened again. The `archiveOpenedViewOnce` Cloud
  /// Function then moves the photo into the private `deleted` archive.
  Future<void> markViewOnceOpened(Message m) async {
    _write(_messages.doc(m.id).update({
      'opened': true,
      'openedAt': FieldValue.serverTimestamp(),
      'url': FieldValue.delete(),
    }));
  }

  /// Removes the message from the chat. The `archiveDeletedMessage` Cloud
  /// Function keeps a copy, and its photo or file, in the `deleted` archive.
  Future<void> deleteMessage(Message m) async {
    _write(_messages.doc(m.id).delete());
  }

  // ------------------------------------------------------------------ files

  static Future<File> localFileFor(Message m) async {
    final dir = await getApplicationDocumentsDirectory();
    return File(
        '${dir.path}/downloads/${m.id}_${_safeName(m.fileName ?? 'file')}');
  }

  /// Downloads a file message to app storage (once) and returns it.
  Future<File> download(Message m, {ProgressCallback? onProgress}) async {
    final file = await localFileFor(m);
    if (await file.exists()) return file;
    final storagePath = m.storagePath;
    if (storagePath == null) throw StateError('This file is no longer available.');

    await file.parent.create(recursive: true);
    final partial = File('${file.path}.part');
    final task = _storage.ref(storagePath).writeToFile(partial);
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    }, onError: (_) {});
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    return partial.rename(file.path);
  }

  // ---------------------------------------------------------------- helpers

  Map<String, dynamic> _base(MessageType type, [ReplyRef? replyTo]) => {
        'senderId': me,
        'type': type.name,
        'seen': false,
        'createdAt': FieldValue.serverTimestamp(),
        if (replyTo != null) 'replyTo': replyTo.toMap(),
      };

  void _write(Future<Object?> write) => write.then((_) {}, onError: onError);

  Future<String> _upload(
    String path, {
    File? file,
    Uint8List? bytes,
    required String mimeType,
    ProgressCallback? onProgress,
  }) async {
    final ref = _storage.ref(path);
    final metadata = SettableMetadata(contentType: mimeType);
    final task =
        file != null ? ref.putFile(file, metadata) : ref.putData(bytes!, metadata);
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    }, onError: (_) {});
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    return ref.getDownloadURL();
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  static String _extension(String name, String fallback) {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? fallback : name.substring(dot + 1).toLowerCase();
  }
}
