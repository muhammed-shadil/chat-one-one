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

String fileExtension(String? name) {
  if (name == null) return '';
  final dot = name.lastIndexOf('.');
  return dot == -1 ? '' : name.substring(dot + 1).toUpperCase();
}
