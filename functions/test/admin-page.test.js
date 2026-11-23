// End-to-end tests for the admin page's functions (adminPhotos, adminPhoto),
// run against the local emulators with `npm test` (never the real project).
//
// Each run uses its own chat ID, so other tests running at the same time
// don't change what's listed for it.

const assert = require('node:assert/strict');
const { test, before } = require('node:test');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  throw new Error('Run these tests with `npm test`, which starts the emulators.');
}

const admin = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { linkSigner } = require('../admin');
const { readLocalSecrets } = require('./local-secret');

const PROJECT = 'chat-one-one-66cbf';
const BUCKET = 'chat-one-one-66cbf.firebasestorage.app';
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT}/asia-south1`;
const PASSWORD = readLocalSecrets().ADMIN_PASSWORD;
const CHAT = `admin-test-${Date.now()}`;
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64',
);

let db, bucket;

const images = (id) => `chats/${CHAT}/images/${id}.png`;
const archived = (id) => `chats/${CHAT}/deleted/${id}/${id}.png`;
const sent = (minutesAgo) => Timestamp.fromMillis(Date.now() - minutesAgo * 60_000);

before(async () => {
  assert.ok(PASSWORD, 'functions/.secret.local should have an ADMIN_PASSWORD (npm test adds one)');
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET }, 'admin-page-test');
  const app = admin.getApp('admin-page-test');
  db = getFirestore(app);
  bucket = getStorage(app).bucket(BUCKET);

  const chat = db.doc(`chats/${CHAT}`);
  const message = (id, data) => chat.collection('messages').doc(id).set({ senderId: 'p1', seen: true, ...data });
  const archive = (id, data) => chat.collection('deleted').doc(id).set({ senderId: 'p1', ...data });
  const upload = (path, bytes = PNG, contentType = 'image/png') =>
    bucket.file(path).save(bytes, { contentType });

  await Promise.all([
    chat.collection('members').doc('p1').set({ name: 'Asha' }),
    chat.collection('members').doc('p2').set({ name: 'Ravi' }),

    message('inchat', { type: 'image', text: 'Beach', storagePath: images('inchat'), createdAt: sent(1), width: 1, height: 1 }),
    upload(images('inchat')),

    message('waiting', { type: 'image', senderId: 'p2', viewOnce: true, opened: false, storagePath: images('waiting'), createdAt: sent(2) }),
    upload(images('waiting')),

    // Opened: the chat keeps an "Opened" stub, the photo is in the archive.
    message('opened', { type: 'image', viewOnce: true, opened: true, storagePath: images('opened'), createdAt: sent(3) }),
    archive('opened', { type: 'image', viewOnce: true, opened: true, reason: 'view_once_opened', storagePath: images('opened'), archivePath: archived('opened'), createdAt: sent(3), openedAt: sent(2) }),
    upload(archived('opened')),

    archive('gone', { type: 'image', reason: 'deleted', storagePath: images('gone'), archivePath: archived('gone'), createdAt: sent(4), deletedAt: sent(1) }),
    upload(archived('gone')),

    message('text', { type: 'text', text: 'hello', createdAt: sent(5) }),
    archive('text_edit_1', { type: 'text', reason: 'edited', text: 'old', newText: 'hello' }),
    message('doc', { type: 'file', mimeType: 'application/pdf', fileName: 'a.pdf', storagePath: `chats/${CHAT}/files/doc/a.pdf`, createdAt: sent(6) }),
    upload(`chats/${CHAT}/files/doc/a.pdf`, Buffer.from('%PDF-1.4'), 'application/pdf'),

    message('nofile', { type: 'image', storagePath: images('nofile'), createdAt: sent(7) }),
    upload(images('orphan')),
  ]);
});

async function listPhotos(password) {
  const res = await fetch(`${FUNCTIONS}/adminPhotos`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ data: { password } }),
  });
  return { status: res.status, body: await res.json() };
}

test('the right password lists every photo of the chat, archived ones included', async () => {
  const { status, body } = await listPhotos(PASSWORD);
  assert.equal(status, 200);
  const { chats, photos, linksExpireAt } = body.result;
  assert.ok(linksExpireAt > Date.now() + 3600_000);
  assert.deepEqual(chats.find((c) => c.id === CHAT), {
    id: CHAT,
    names: { p1: 'Asha', p2: 'Ravi' },
    photoCount: 6,
  });

  const mine = photos.filter((p) => p.chatId === CHAT);
  assert.deepEqual(
    mine.map((p) => [p.messageId, p.status, p.url !== null]),
    [
      // Its upload time is all there is, and it was uploaded just now.
      ['orphan', 'unlinked', true],
      ['inchat', 'chat', true],
      ['waiting', 'view_once', true],
      ['opened', 'opened', true],
      ['gone', 'deleted', true],
      ['nofile', 'chat', false],
    ],
  );
  assert.equal(mine[1].caption, 'Beach');
  assert.equal(mine[1].size, PNG.length);
  assert.equal(mine.find((p) => p.messageId === 'opened').path, archived('opened'));
});

test('a signed link shows the archived photo, without giving it a download link', async () => {
  const { body } = await listPhotos(PASSWORD);
  const opened = body.result.photos.find((p) => p.key === `${CHAT}/opened`);

  const res = await fetch(opened.url);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('content-type'), 'image/png');
  assert.equal(res.headers.get('access-control-allow-origin'), '*');
  assert.match(res.headers.get('cache-control'), /^private, max-age=\d+$/);
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), PNG);

  const [metadata] = await bucket.file(archived('opened')).getMetadata();
  assert.equal(metadata.metadata?.firebaseStorageDownloadTokens, undefined);
});

test('changed, expired or made-up links are refused', async () => {
  const { body } = await listPhotos(PASSWORD);
  const url = new URL(body.result.photos.find((p) => p.key === `${CHAT}/opened`).url);

  const otherPath = new URL(url);
  otherPath.searchParams.set('path', archived('gone'));
  const badSig = new URL(url);
  badSig.searchParams.set('sig', 'x'.repeat(43));
  const later = new URL(url);
  later.searchParams.set('exp', String(Number(url.searchParams.get('exp')) + 3600));
  const noParams = new URL(url.origin + url.pathname);

  for (const u of [otherPath, badSig, later, noParams]) {
    const res = await fetch(u);
    assert.equal(res.status, 403, u.search);
  }

  // Correctly signed, but already past its expiry.
  const signer = linkSigner(PASSWORD);
  const past = String(Math.floor(Date.now() / 1000) - 60);
  const expired = new URL(url);
  expired.searchParams.set('exp', past);
  expired.searchParams.set('sig', signer.sign(archived('opened'), past));
  const res = await fetch(expired);
  assert.equal(res.status, 403);
  assert.match(await res.text(), /expired/);
});

test('signed links only ever send photos', async () => {
  const signer = linkSigner(PASSWORD);
  const exp = String(Math.floor(Date.now() / 1000) + 600);
  const link = (path) =>
    `${FUNCTIONS}/adminPhoto?${new URLSearchParams({ path, exp, sig: signer.sign(path, exp) })}`;

  assert.equal((await fetch(link(`chats/${CHAT}/files/doc/a.pdf`))).status, 415);
  assert.equal((await fetch(link(images('nofile')))).status, 404);
  assert.equal((await fetch(link(images('inchat')), { method: 'POST' })).status, 405);
});

test('a wrong or missing password lists nothing', async () => {
  for (const password of ['wrong password!!', undefined, '']) {
    const { status, body } = await listPhotos(password);
    assert.equal(status, 403);
    assert.equal(body.error.status, 'PERMISSION_DENIED');
    assert.equal(body.result, undefined);
  }
});
