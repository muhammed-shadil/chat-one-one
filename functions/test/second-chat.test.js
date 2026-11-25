// End-to-end tests for the second chat, run against the local emulators with
// `npm test` (never the real project). They check that it works like the
// first chat and that the two never see each other's photos or admin page.

const assert = require('node:assert/strict');
const { test, before, after } = require('node:test');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  throw new Error('Run these tests with `npm test`, which starts the emulators.');
}

const admin = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { initializeApp, deleteApp } = require('firebase/app');
const client = require('firebase/firestore');
const clientStorage = require('firebase/storage');
const { linkSigner } = require('../admin');
const { FIRST_CHAT, SECOND_CHAT } = require('../chats');
const { readLocalSecrets } = require('./local-secret');

const PROJECT = 'chat-one-one-66cbf';
const BUCKET = 'chat-one-one-66cbf.firebasestorage.app';
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT}/asia-south1`;
const { ADMIN_PASSWORD: PASSWORD_1, ADMIN_PASSWORD_2: PASSWORD_2 } = readLocalSecrets();
const SECOND = SECOND_CHAT.id;
// Stands in for the first chat's photos; the first admin page lists every
// chat except the second.
const OTHER = `first-scope-test-${Date.now()}`;
const RUN = Date.now().toString(36);
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64',
);

let app, db, storage, adminDb, bucket;

const images = (chat, id) => `chats/${chat}/images/${id}.png`;

before(async () => {
  assert.ok(PASSWORD_1 && PASSWORD_2, 'functions/.secret.local should have both passwords (npm test adds them)');
  assert.notEqual(PASSWORD_1, PASSWORD_2);
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET }, 'second-chat-test');
  const adminApp = admin.getApp('second-chat-test');
  adminDb = getFirestore(adminApp);
  bucket = getStorage(adminApp).bucket(BUCKET);

  app = initializeApp({ projectId: PROJECT, apiKey: 'test', storageBucket: BUCKET });
  db = client.getFirestore(app);
  storage = clientStorage.getStorage(app);
  const [fsHost, fsPort] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const [stHost, stPort] = process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(':');
  client.connectFirestoreEmulator(db, fsHost, Number(fsPort));
  clientStorage.connectStorageEmulator(storage, stHost, Number(stPort));

  // One photo in each chat, for the admin pages.
  const photo = async (chat, id, name) => {
    await bucket.file(images(chat, id)).save(PNG, { contentType: 'image/png' });
    await adminDb.doc(`chats/${chat}/members/p1`).set({ name });
    await adminDb.doc(`chats/${chat}/messages/${id}`).set({
      senderId: 'p1',
      type: 'image',
      seen: false,
      storagePath: images(chat, id),
      createdAt: Timestamp.now(),
    });
  };
  await Promise.all([photo(SECOND, `second_${RUN}`, 'Zara'), photo(OTHER, `other_${RUN}`, 'Asha')]);
});

after(async () => {
  await client.terminate(db);
  await deleteApp(app);
});

async function assertDenied(promise) {
  await assert.rejects(promise, (e) => /permission|unauthorized/i.test(`${e.code} ${e.message}`));
}

async function listPhotos(fn, password) {
  const res = await fetch(`${FUNCTIONS}/${fn}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ data: { password } }),
  });
  return { status: res.status, body: await res.json() };
}

function signedLink(fn, password, path) {
  const exp = String(Math.floor(Date.now() / 1000) + 600);
  const sig = linkSigner(password).sign(path, exp);
  return `${FUNCTIONS}/${fn}?${new URLSearchParams({ path, exp, sig })}`;
}

// -------------------------------------------------------------------- rules

test('the second chat can send, read and react like the first', async () => {
  const messages = client.collection(db, 'chats', SECOND, 'messages');
  const ref = client.doc(messages);
  const path = images(SECOND, ref.id);
  const object = clientStorage.ref(storage, path);
  await clientStorage.uploadBytes(object, PNG, { contentType: 'image/png' });
  await client.setDoc(ref, {
    senderId: 'p2',
    type: 'image',
    seen: false,
    storagePath: path,
    url: await clientStorage.getDownloadURL(object),
    createdAt: client.serverTimestamp(),
  });
  await client.updateDoc(ref, { seen: true, 'reactions.p1': '❤️' });
  assert.equal((await client.getDoc(ref)).data().seen, true);
  assert.deepEqual(Buffer.from(await clientStorage.getBytes(object)), PNG);

  const member = client.doc(db, 'chats', SECOND, 'members', 'p2');
  await client.setDoc(member, { name: 'Zara', online: true }, { merge: true });
  assert.equal((await client.getDoc(member)).data().name, 'Zara');

  await assertDenied(client.updateDoc(ref, { senderId: 'p1' }));
  await assertDenied(client.setDoc(client.doc(db, 'chats', SECOND, 'members', 'p3'), { name: 'x' }));
  await assertDenied(clientStorage.deleteObject(object));
});

test('the second chat cannot see its archive, and unknown chats are refused', async () => {
  await assertDenied(client.getDocs(client.collection(db, 'chats', SECOND, 'deleted')));
  await assertDenied(
    clientStorage.uploadBytes(clientStorage.ref(storage, `chats/${SECOND}/deleted/x/y.png`), PNG),
  );

  const stranger = 'not-a-real-chat-id';
  await assertDenied(client.getDocs(client.collection(db, 'chats', stranger, 'messages')));
  await assertDenied(
    client.addDoc(client.collection(db, 'chats', stranger, 'messages'), { senderId: 'p1', type: 'text' }),
  );
  await assertDenied(client.getDoc(client.doc(db, 'chats', stranger, 'members', 'p1')));
  await assertDenied(
    clientStorage.uploadBytes(clientStorage.ref(storage, `chats/${stranger}/images/x.png`), PNG),
  );
  await assertDenied(client.getDocs(client.collection(db, 'chats')));
});

// ------------------------------------------------------------------ archive

test('an opened view-once photo in the second chat goes to its own archive', async () => {
  const ref = client.doc(client.collection(db, 'chats', SECOND, 'messages'));
  const path = images(SECOND, ref.id);
  await clientStorage.uploadBytes(clientStorage.ref(storage, path), PNG, { contentType: 'image/png' });
  await client.setDoc(ref, {
    senderId: 'p1',
    type: 'image',
    seen: false,
    viewOnce: true,
    opened: false,
    storagePath: path,
    createdAt: client.serverTimestamp(),
  });
  await client.updateDoc(ref, { opened: true, openedAt: client.serverTimestamp() });

  const archiveDoc = adminDb.doc(`chats/${SECOND}/deleted/${ref.id}`);
  const deadline = Date.now() + 30_000;
  let snap;
  while (!(snap = await archiveDoc.get()).exists && Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 250));
  }
  assert.ok(snap.exists, 'archived in time');
  assert.equal(snap.get('reason'), 'view_once_opened');
  assert.equal(snap.get('archivePath'), `chats/${SECOND}/deleted/${ref.id}/${ref.id}.png`);
  assert.equal((await bucket.file(snap.get('archivePath')).exists())[0], true);
  assert.equal((await bucket.file(path).exists())[0], false);
  // Nothing landed in the first chat.
  assert.equal((await adminDb.doc(`chats/${FIRST_CHAT.id}/deleted/${ref.id}`).get()).exists, false);
});

// --------------------------------------------------------------- admin pages

test("the second admin page lists only the second chat's photos", async () => {
  const { status, body } = await listPhotos('adminPhotos2', PASSWORD_2);
  assert.equal(status, 200);
  const { chats, photos } = body.result;
  assert.deepEqual(chats.map((c) => c.id), [SECOND]);
  assert.equal(chats[0].names.p1, 'Zara');
  assert.ok(photos.length > 0);
  assert.ok(photos.every((p) => p.chatId === SECOND && p.path.startsWith(`chats/${SECOND}/`)));

  const mine = photos.find((p) => p.messageId === `second_${RUN}`);
  assert.ok(mine, 'the seeded photo is listed');
  assert.ok(mine.url.startsWith(`${FUNCTIONS}/adminPhoto2?`));
  const res = await fetch(mine.url);
  assert.equal(res.status, 200);
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), PNG);
});

test("the first admin page never lists the second chat's photos", async () => {
  const { status, body } = await listPhotos('adminPhotos', PASSWORD_1);
  assert.equal(status, 200);
  const { chats, photos } = body.result;
  assert.ok(photos.some((p) => p.messageId === `other_${RUN}`), 'it still lists the other chats');
  assert.ok(!chats.some((c) => c.id === SECOND));
  assert.ok(!photos.some((p) => p.chatId === SECOND || p.path?.includes(SECOND)));
  assert.ok(photos.every((p) => !p.url || p.url.startsWith(`${FUNCTIONS}/adminPhoto?`)));
});

test("each admin page refuses the other chat's password", async () => {
  for (const [fn, password] of [
    ['adminPhotos', PASSWORD_2],
    ['adminPhotos2', PASSWORD_1],
    ['adminPhotos2', 'wrong password!!'],
    ['adminPhotos2', undefined],
  ]) {
    const { status, body } = await listPhotos(fn, password);
    assert.equal(status, 403, fn);
    assert.equal(body.result, undefined);
  }
});

test("each photo function refuses the other chat's photos, even with a valid signature", async () => {
  const second = images(SECOND, `second_${RUN}`);
  const other = images(OTHER, `other_${RUN}`);

  // Sanity: correctly signed links to a page's own chat work.
  assert.equal((await fetch(signedLink('adminPhoto2', PASSWORD_2, second))).status, 200);
  assert.equal((await fetch(signedLink('adminPhoto', PASSWORD_1, other))).status, 200);

  // The other chat's path, signed with the page's own password.
  assert.equal((await fetch(signedLink('adminPhoto', PASSWORD_1, second))).status, 403);
  assert.equal((await fetch(signedLink('adminPhoto2', PASSWORD_2, other))).status, 403);
  // The page's own path, signed with the other chat's password.
  assert.equal((await fetch(signedLink('adminPhoto', PASSWORD_2, other))).status, 403);
  assert.equal((await fetch(signedLink('adminPhoto2', PASSWORD_1, second))).status, 403);
});
