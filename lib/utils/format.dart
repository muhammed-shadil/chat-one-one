import 'package:intl/intl.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[i]}';
}

String formatTime(DateTime t) => DateFormat.jm().format(t);

/// "0:07", "12:45", "1:02:03".
String formatDuration(Duration d) {
  final s = d.inSeconds;
  final mmss = '${(s ~/ 60) % 60}:${(s % 60).toString().padLeft(2, '0')}';
  if (s < 3600) return mmss;
  return '${s ~/ 3600}:${mmss.padLeft(5, '0')}';
}

/// Web addresses in [text], as (start, end) ranges.
Iterable<(int, int)> findLinks(String text) sync* {
  for (final m in _link.allMatches(text)) {
    var end = m.end;
    // Leave trailing punctuation out of the link: "see example.com."
    while (end > m.start && '.,!?;:)]\'"'.contains(text[end - 1])) {
      end--;
    }
    yield (m.start, end);
  }
}

final _link = RegExp(r'(?:https?://|www\.)[^\s<>]+', caseSensitive: false);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Today", "Yesterday", a weekday within the last week, else a date.
String formatDay(DateTime t, {DateTime? now}) {
  now ??= DateTime.now();
  // Compare calendar days in UTC so daylight-saving shifts don't skew the count.
  final days = DateTime.utc(now.year, now.month, now.day)
      .difference(DateTime.utc(t.year, t.month, t.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return DateFormat.EEEE().format(t);
  if (t.year == now.year) return DateFormat('d MMMM').format(t);
  return DateFormat('d MMMM y').format(t);
}

String formatLastSeen(DateTime t, {DateTime? now}) {
  final day = formatDay(t, now: now);
  final when = switch (day) {
    'Today' => 'today',
    'Yesterday' => 'yesterday',
    _ => day,
  };
  return 'last seen $when at ${formatTime(t)}';
}

/// "Today at 3:42 PM", "2 March at 9:05 AM".
String formatMoment(DateTime t, {DateTime? now}) {
  final local = t.toLocal();
  return '${formatDay(local, now: now)} at ${formatTime(local)}';
}

/// "12.971599, 77.594566": six decimals is about 10 cm.
String formatCoordinates(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

/// "± 12 m", "± 1.5 km".
String formatAccuracy(double meters) => meters < 1000
    ? '± ${meters.round()} m'
    : '± ${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';

/// "7 days", "1 day", "12 hours".
String formatRetention(Duration d) {
  if (d.inDays >= 1) return d.inDays == 1 ? '1 day' : '${d.inDays} days';
  final hours = d.inHours < 1 ? 1 : d.inHours;
  return hours == 1 ? '1 hour' : '$hours hours';
}

String fileExtension(String? name) {
  if (name == null) return '';
  final dot = name.lastIndexOf('.');
  return dot == -1 ? '' : name.substring(dot + 1).toUpperCase();
}
