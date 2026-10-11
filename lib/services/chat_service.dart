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
/// Storage layout:
///   chats/{kChatId}/images/{messageId}.{ext}
///   chats/{kChatId}/files/{messageId}/{fileName}
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

  // --------------------------------------------------------------- messages

  /// Newest first.
  Stream<List<Message>> watchMessages(int limit) => _messages
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(Message.fromDoc).toList());

  void sendText(String text) => _write(_messages.add({
        ..._base(MessageType.text),
        'text': text,
      }));

  Future<void> sendImage({
    required Uint8List bytes,
    required String name,
    required int width,
    required int height,
    String? caption,
    bool viewOnce = false,
    ProgressCallback? onProgress,
  }) async {
    final doc = _messages.doc();
    final mimeType = lookupMimeType(name, headerBytes: bytes) ?? 'image/jpeg';
    final path = 'chats/$kChatId/images/${doc.id}.${_extension(name, 'jpg')}';
    final url = await _upload(path,
        bytes: bytes, mimeType: mimeType, onProgress: onProgress);
    _write(doc.set({
      ..._base(MessageType.image),
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

  Future<void> sendFile(
    PlatformFile picked, {
    required int size,
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
      ..._base(MessageType.file),
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

  /// Called by the receiver once a view-once photo is on screen: the photo is
  /// deleted from Storage and its link removed, so it can't be opened again.
  Future<void> markViewOnceOpened(Message m) async {
    _write(_messages.doc(m.id).update({
      'opened': true,
      'openedAt': FieldValue.serverTimestamp(),
      'url': FieldValue.delete(),
    }));
    await _deleteObject(m.storagePath);
  }

  Future<void> deleteMessage(Message m) async {
    _write(_messages.doc(m.id).delete());
    await _deleteObject(m.storagePath);
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

  Map<String, dynamic> _base(MessageType type) => {
        'senderId': me,
        'type': type.name,
        'seen': false,
        'createdAt': FieldValue.serverTimestamp(),
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

  Future<void> _deleteObject(String? path) async {
    if (path == null) return;
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') onError(e);
    }
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  static String _extension(String name, String fallback) {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? fallback : name.substring(dot + 1).toLowerCase();
  }
}
