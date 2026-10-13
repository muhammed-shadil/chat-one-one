import 'package:chat_one_one/models/message.dart';
import 'package:chat_one_one/utils/format.dart';
import 'package:chat_one_one/widgets/reply_quote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 7)), '0:07');
    expect(formatDuration(const Duration(minutes: 12, seconds: 45)), '12:45');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03');
  });

  test('findLinks', () {
    List<String> links(String s) =>
        [for (final (a, b) in findLinks(s)) s.substring(a, b)];
    expect(links('see https://example.com/a?b=1.'), ['https://example.com/a?b=1']);
    expect(links('(www.example.org) and HTTP://X.IO!'),
        ['www.example.org', 'HTTP://X.IO']);
    expect(links('no links here, just example.com'), isEmpty);
  });

  test('a reply quotes a short stand-in for the message', () {
    (IconData?, String) quote(MessageType type,
            {String? text, String? fileName, int? durationMs, bool viewOnce = false}) =>
        ReplyQuote.describe(ReplyRef.of(Message(
            id: 'm1',
            senderId: 'p1',
            type: type,
            text: text,
            fileName: fileName,
            durationMs: durationMs,
            viewOnce: viewOnce)));

    expect(quote(MessageType.text, text: 'hi'), (null, 'hi'));
    expect(quote(MessageType.image), (Icons.photo, 'Photo'));
    expect(quote(MessageType.image, text: 'Beach'), (Icons.photo, 'Beach'));
    expect(quote(MessageType.image, viewOnce: true).$2, 'View once photo');
    expect(quote(MessageType.audio, durationMs: 65000), (Icons.mic, 'Voice message (1:05)'));
    expect(quote(MessageType.file, fileName: 'a.pdf'), (Icons.insert_drive_file, 'a.pdf'));
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(25 * 1024 * 1024), '25 MB');
  });

  test('formatDay', () {
    final now = DateTime(2026, 10, 11, 9);
    expect(formatDay(DateTime(2026, 10, 11, 0, 5), now: now), 'Today');
    expect(formatDay(DateTime(2026, 10, 10, 23), now: now), 'Yesterday');
    expect(formatDay(DateTime(2026, 10, 7), now: now), 'Wednesday');
    expect(formatDay(DateTime(2026, 3, 2), now: now), '2 March');
    expect(formatDay(DateTime(2025, 3, 2), now: now), '2 March 2025');
  });

  test('fileExtension', () {
    expect(fileExtension('report.final.pdf'), 'PDF');
    expect(fileExtension('README'), '');
  });
}
