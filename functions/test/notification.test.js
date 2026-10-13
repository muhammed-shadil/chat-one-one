// What push notifications say. Plain unit tests: no emulators needed.

const assert = require('node:assert/strict');
const { test } = require('node:test');
const { notificationFor, formatDuration } = require('../notification');

test('a text shows who sent it and what it says', () => {
  assert.deepEqual(notificationFor({ type: 'text', text: 'On my way' }, 'Asha'), {
    title: 'Asha',
    body: 'On my way',
  });
});

test('long texts are cut short', () => {
  const { body } = notificationFor({ type: 'text', text: 'a'.repeat(500) }, 'Asha');
  assert.equal(body, `${'a'.repeat(200)}…`);
});

test('photos show their caption, or just "Photo"', () => {
  assert.equal(notificationFor({ type: 'image', text: 'Beach' }, 'Asha').body, '📷 Beach');
  assert.equal(notificationFor({ type: 'image' }, 'Asha').body, '📷 Photo');
});

test('view-once photos never reveal anything', () => {
  const m = { type: 'image', viewOnce: true, text: 'secret caption' };
  assert.equal(notificationFor(m, 'Asha').body, '📷 View once photo');
});

test('voice messages show their length, files their name', () => {
  assert.equal(
    notificationFor({ type: 'audio', durationMs: 12_400 }, 'Asha').body,
    '🎤 Voice message (0:12)',
  );
  assert.equal(
    notificationFor({ type: 'file', fileName: 'report.pdf' }, 'Asha').body,
    '📄 report.pdf',
  );
});

test('a sender without a name yet still gets a title', () => {
  assert.equal(notificationFor({ type: 'text', text: 'hi' }, undefined).title, 'New message');
});

test('durations match the app', () => {
  assert.equal(formatDuration(7_000), '0:07');
  assert.equal(formatDuration(765_000), '12:45');
  assert.equal(formatDuration(3_723_000), '1:02:03');
});
