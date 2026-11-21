import 'package:cloud_firestore/cloud_firestore.dart';

/// A position measured once on this device.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;

  /// In meters: the real position is most likely within this radius.
  final double accuracy;

  /// When the device measured it.
  final DateTime capturedAt;

  /// Worse than this is no use for finding someone. Same as `firestore.rules`.
  static const maxAccuracy = 100000.0;

  /// Real coordinates and a usable accuracy. Matches `firestore.rules`.
  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      accuracy.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      accuracy >= 0 &&
      accuracy <= maxAccuracy;
}

/// A location someone chose to share one time. There is no tracking: it is
/// only ever updated when they share again.
///
/// Stored in `chats/{kChatId}/locations/{p1|p2}`, one per person, so sharing
/// again replaces the previous one rather than adding another.
class SharedLocation {
  const SharedLocation({
    required this.userId,
    required this.fix,
    required this.expiresAt,
    this.sharedAt,
  });

  /// The only kind there is; written so the rules can insist on it.
  static const sharingType = 'one_time';

  /// Who shared it (p1 / p2), which is also the document ID.
  final String userId;
  final LocationFix fix;

  /// When it reached the server; null until then.
  final DateTime? sharedAt;

  /// After this the security rules refuse to return it.
  final DateTime expiresAt;

  bool isExpired([DateTime? now]) => !(now ?? DateTime.now()).isBefore(expiresAt);

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        'accuracy': fix.accuracy,
        'capturedAt': Timestamp.fromDate(fix.capturedAt),
        'sharedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'sharingType': sharingType,
      };

  /// Null if there is no document, or it's missing something.
  static SharedLocation? fromMap(String id, Map<String, dynamic>? d) {
    if (d == null) return null;
    final lat = d['latitude'], lng = d['longitude'], acc = d['accuracy'];
    final captured = d['capturedAt'], expires = d['expiresAt'];
    if (lat is! num || lng is! num || acc is! num) return null;
    if (captured is! Timestamp || expires is! Timestamp) return null;
    final fix = LocationFix(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      accuracy: acc.toDouble(),
      capturedAt: captured.toDate(),
    );
    if (!fix.isValid) return null;
    return SharedLocation(
      userId: id,
      fix: fix,
      sharedAt: (d['sharedAt'] as Timestamp?)?.toDate(),
      expiresAt: expires.toDate(),
    );
  }
}
