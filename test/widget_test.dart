import 'package:chat_one_one/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
