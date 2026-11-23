// What the admin page lists, and how its links are signed. Plain unit tests:
// no emulators needed.

const assert = require('node:assert/strict');
const { test } = require('node:test');
const {
  passwordIsSetUp,
  passwordMatches,
  linkSigner,
  linkExpiry,
  photoLink,
  buildPhotoList,
} = require('../admin');

const PASSWORD = 'correct horse battery';
const at = (ms) => ({ toMillis: () => ms });
const link = (path) => `link:${path}`;

test('only the right password, of at least 12 characters, opens the page', () => {
  assert.equal(passwordMatches(PASSWORD, PASSWORD), true);
  assert.equal(passwordMatches('correct horse', PASSWORD), false);
  assert.equal(passwordMatches(undefined, PASSWORD), false);
  assert.equal(passwordMatches({}, PASSWORD), false);
  assert.equal(passwordIsSetUp('short'), false);
  assert.equal(passwordMatches('short', 'short'), false);
  assert.equal(passwordMatches('', undefined), false);
});

test('signed links only work for the path and expiry they were made for', () => {
  const signer = linkSigner(PASSWORD);
  const sig = signer.sign('chats/c/deleted/m/m.jpg', '7200');
  assert.equal(signer.verify('chats/c/deleted/m/m.jpg', '7200', sig), true);
  assert.equal(signer.verify('chats/c/deleted/x/x.jpg', '7200', sig), false);
  assert.equal(signer.verify('chats/c/deleted/m/m.jpg', '9999', sig), false);
  assert.equal(signer.verify('chats/c/deleted/m/m.jpg', '7200', `${sig}x`), false);
  assert.equal(signer.verify('chats/c/deleted/m/m.jpg', '7200', undefined), false);
  assert.equal(signer.verify(['a', 'b'], '7200', sig), false);
  // A new password cancels old links.
  assert.equal(linkSigner('another password!').verify('chats/c/deleted/m/m.jpg', '7200', sig), false);
});

test('links last one to two hours and stay the same within an hour', () => {
  const start = Date.UTC(2026, 10, 21, 10, 0, 0);
  for (const offset of [0, 1, 30 * 60_000, 60 * 60_000 - 1]) {
    const exp = linkExpiry(start + offset);
    assert.equal(exp, start / 1000 + 2 * 3600);
    const left = exp - (start + offset) / 1000;
    assert.ok(left > 3600 && left <= 7200);
  }
  assert.equal(linkExpiry(start + 60 * 60_000), start / 1000 + 3 * 3600);
});

test('a link carries the path, expiry and signature', () => {
  const signer = linkSigner(PASSWORD);
  const url = new URL(photoLink('https://x.test/adminPhoto', signer, 'chats/c/images/a b.jpg', 7200));
  assert.equal(url.searchParams.get('path'), 'chats/c/images/a b.jpg');
  assert.equal(url.searchParams.get('exp'), '7200');
  assert.equal(signer.verify('chats/c/images/a b.jpg', '7200', url.searchParams.get('sig')), true);
});

test('every photo is listed with where it is now, newest first', () => {
  const files = [
    { path: 'chats/c/images/chat.jpg', size: '100', contentType: 'image/jpeg' },
    { path: 'chats/c/images/waiting.jpg', size: '200', contentType: 'image/jpeg' },
    { path: 'chats/c/deleted/opened/opened.jpg', size: '300', contentType: 'image/jpeg' },
    { path: 'chats/c/deleted/gone/gone.png', size: '400', contentType: 'image/png' },
    { path: 'chats/c/files/asfile/pic.webp', size: '500', contentType: 'image/webp' },
    { path: 'chats/c/files/doc/report.pdf', size: '600', contentType: 'application/pdf' },
    { path: 'chats/c/audio/voice.m4a', size: '700', contentType: 'audio/mp4' },
    { path: 'chats/c/images/orphan.jpg', size: '800', contentType: 'image/jpeg', timeCreated: '1970-01-01T00:00:00.500Z' },
  ];
  const chats = [
    {
      id: 'c',
      members: { p1: { name: 'Asha' }, p2: { name: 'Ravi' } },
      messages: [
        { id: 'chat', data: { type: 'image', senderId: 'p1', text: 'Beach', storagePath: 'chats/c/images/chat.jpg', createdAt: at(1000), width: 4, height: 3 } },
        { id: 'waiting', data: { type: 'image', senderId: 'p2', viewOnce: true, opened: false, storagePath: 'chats/c/images/waiting.jpg', createdAt: at(2000) } },
        // An opened view-once photo stays in the chat as "Opened".
        { id: 'opened', data: { type: 'image', senderId: 'p1', viewOnce: true, opened: true, storagePath: 'chats/c/images/opened.jpg', createdAt: at(3000) } },
        { id: 'asfile', data: { type: 'file', mimeType: 'image/webp', fileName: 'pic.webp', senderId: 'p2', storagePath: 'chats/c/files/asfile/pic.webp', createdAt: at(5000) } },
        { id: 'doc', data: { type: 'file', mimeType: 'application/pdf', storagePath: 'chats/c/files/doc/report.pdf', createdAt: at(6000) } },
        { id: 'missing', data: { type: 'image', senderId: 'p1', storagePath: 'chats/c/images/missing.jpg', createdAt: at(7000) } },
      ],
      archived: [
        { id: 'opened', data: { type: 'image', senderId: 'p1', viewOnce: true, opened: true, reason: 'view_once_opened', storagePath: 'chats/c/images/opened.jpg', archivePath: 'chats/c/deleted/opened/opened.jpg', createdAt: at(3000), openedAt: at(3500) } },
        { id: 'gone', data: { type: 'image', senderId: 'p2', reason: 'deleted', storagePath: 'chats/c/images/gone.png', archivePath: 'chats/c/deleted/gone/gone.png', createdAt: at(4000), deletedAt: at(4500) } },
        { id: 'x_edit_1', data: { type: 'text', reason: 'edited', text: 'old words' } },
      ],
    },
  ];

  const { chats: chatList, photos } = buildPhotoList(chats, files, link);

  assert.deepEqual(
    photos.map((p) => [p.messageId, p.status, p.url]),
    [
      ['missing', 'chat', null],
      ['asfile', 'chat', 'link:chats/c/files/asfile/pic.webp'],
      ['gone', 'deleted', 'link:chats/c/deleted/gone/gone.png'],
      ['opened', 'opened', 'link:chats/c/deleted/opened/opened.jpg'],
      ['waiting', 'view_once', 'link:chats/c/images/waiting.jpg'],
      ['chat', 'chat', 'link:chats/c/images/chat.jpg'],
      ['orphan', 'unlinked', 'link:chats/c/images/orphan.jpg'],
    ],
  );
  assert.deepEqual(photos.find((p) => p.messageId === 'chat'), {
    key: 'c/chat',
    chatId: 'c',
    messageId: 'chat',
    senderId: 'p1',
    status: 'chat',
    viewOnce: false,
    caption: 'Beach',
    fileName: null,
    sentAt: 1000,
    openedAt: null,
    deletedAt: null,
    width: 4,
    height: 3,
    size: 100,
    path: 'chats/c/images/chat.jpg',
    url: 'link:chats/c/images/chat.jpg',
  });
  const opened = photos.find((p) => p.messageId === 'opened');
  assert.equal(opened.viewOnce, true);
  assert.equal(opened.openedAt, 3500);
  assert.equal(photos.find((p) => p.messageId === 'gone').deletedAt, 4500);
  const orphan = photos.find((p) => p.status === 'unlinked');
  assert.equal(orphan.sentAt, Date.parse('1970-01-01T00:00:00.500Z'));
  assert.equal(orphan.fileName, 'orphan.jpg');
  assert.equal(orphan.size, 800);

  assert.deepEqual(chatList, [{ id: 'c', names: { p1: 'Asha', p2: 'Ravi' }, photoCount: 7 }]);
});

test('an archive entry whose move failed points at the file where it still is', () => {
  const files = [{ path: 'chats/c/images/m.jpg', size: '1', contentType: 'image/jpeg' }];
  const chats = [{
    id: 'c',
    members: {},
    messages: [],
    archived: [{ id: 'm', data: { type: 'image', reason: 'deleted', storagePath: 'chats/c/images/m.jpg' } }],
  }];
  const [photo] = buildPhotoList(chats, files, link).photos;
  assert.equal(photo.status, 'deleted');
  assert.equal(photo.url, 'link:chats/c/images/m.jpg');
});

test('a view-once photo opened before its archive entry exists still counts as opened', () => {
  const chats = [{
    id: 'c',
    members: {},
    messages: [{ id: 'm', data: { type: 'image', viewOnce: true, opened: true, storagePath: 'chats/c/images/m.jpg' } }],
    archived: [],
  }];
  const [photo] = buildPhotoList(chats, [], link).photos;
  assert.equal(photo.status, 'opened');
  assert.equal(photo.url, null);
});

test('photos in Storage under another chat ID are listed with that chat', () => {
  const files = [{ path: 'chats/old/deleted/m1/m1.jpg', size: '9', contentType: 'image/jpeg' }];
  const { chats, photos } = buildPhotoList([], files, link);
  assert.equal(photos[0].chatId, 'old');
  assert.equal(photos[0].messageId, 'm1');
  assert.deepEqual(chats, [{ id: 'old', names: {}, photoCount: 1 }]);
});
