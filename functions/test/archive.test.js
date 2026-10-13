// End-to-end tests for the archive functions and the security rules, run
// against the local emulators with `npm test` (never the real project).
//
// The app's side is played by the Firebase JS client SDK, so the security
// rules apply exactly as they do to the phones and the website. Results are
// checked with the Admin SDK, which can see the private archive.

const assert = require('node:assert/strict');
const { test, before, after } = require('node:test');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  throw new Error('Run these tests with `npm test`, which starts the emulators.');
}

const admin = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { initializeApp, deleteApp } = require('firebase/app');
const client = require('firebase/firestore');
const clientStorage = require('firebase/storage');

const PROJECT = 'chat-one-one-66cbf';
const BUCKET = 'chat-one-one-66cbf.firebasestorage.app';
const CHAT = 'rhxd7yqwcq6xant5r6k5nzvx'; // kChatId in lib/config.dart
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64',
);

let app, db, storage, adminDb, bucket;

before(() => {
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  adminDb = getFirestore();
  bucket = getStorage().bucket(BUCKET);

  app = initializeApp({ projectId: PROJECT, apiKey: 'test', storageBucket: BUCKET });
  db = client.getFirestore(app);
  storage = clientStorage.getStorage(app);
  const [fsHost, fsPort] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const [stHost, stPort] = process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(':');
  client.connectFirestoreEmulator(db, fsHost, Number(fsPort));
  clientStorage.connectStorageEmulator(storage, stHost, Number(stPort));
});

after(async () => {
  await client.terminate(db);
  await deleteApp(app);
});

// ------------------------------------------------------------------ helpers

const messages = () => client.collection(db, 'chats', CHAT, 'messages');
const archiveDoc = (id) => adminDb.doc(`chats/${CHAT}/deleted/${id}`);

// Sends a message the way lib/services/chat_service.dart does.
async function send(fields, file) {
  const ref = client.doc(messages());
  let extra = {};
  if (file) {
    const path = file.path(ref.id);
    const object = clientStorage.ref(storage, path);
    await clientStorage.uploadBytes(object, file.bytes, { contentType: file.mimeType });
    extra = {
      url: await clientStorage.getDownloadURL(object),
      storagePath: path,
      mimeType: file.mimeType,
    };
  }
  await client.setDoc(ref, {
    senderId: 'p1',
    seen: false,
    createdAt: client.serverTimestamp(),
    ...extra,
    ...fields,
  });
  return { id: ref.id, ref, storagePath: extra.storagePath };
}

const sendViewOnce = () =>
  send(
    { type: 'image', width: 1, height: 1, viewOnce: true, opened: false },
    { path: (id) => `chats/${CHAT}/images/${id}.png`, bytes: PNG, mimeType: 'image/png' },
  );

// What the receiver's app does once a view-once photo is on screen.
const open = (m) =>
  client.updateDoc(m.ref, {
    opened: true,
    openedAt: client.serverTimestamp(),
    url: client.deleteField(),
  });

// The functions run in the background, so poll until the archive matches.
async function waitForArchive(id, until = (d) => d) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const snap = await archiveDoc(id).get();
    if (snap.exists && until(snap.data())) return snap.data();
    await new Promise((r) => setTimeout(r, 250));
  }
  assert.fail(`message ${id} was not archived in time`);
}

const fileExists = async (path) => (await bucket.file(path).exists())[0];

async function assertDenied(promise) {
  await assert.rejects(promise, (e) =>
    /permission|unauthorized/i.test(`${e.code} ${e.message}`),
  );
}

// -------------------------------------------------------------------- tests

test('an opened view-once photo moves to the archive, and the chat shows "Opened"', async () => {
  const m = await sendViewOnce();
  await open(m);

  const archived = await waitForArchive(m.id);
  const archivePath = `chats/${CHAT}/deleted/${m.id}/${m.id}.png`;
  assert.equal(archived.reason, 'view_once_opened');
  assert.equal(archived.archivePath, archivePath);
  assert.equal(archived.viewOnce, true);
  assert.equal(archived.opened, true);
  assert.ok(archived.openedAt, 'openedAt is kept');
  assert.ok(archived.createdAt, 'createdAt is kept');
  assert.equal(archived.url, undefined, 'the dead link is not copied');

  // The photo moved, byte for byte. (Removing its download token can't be
  // checked here: the Storage emulator keeps tokens apart from the metadata
  // and never drops them, while real Cloud Storage deletes a key set to null.)
  assert.equal(await fileExists(m.storagePath), false, 'original is removed');
  const [bytes] = await bucket.file(archivePath).download();
  assert.deepEqual(bytes, PNG);

  // The chat still has the message, marked opened, with no link.
  const inChat = (await client.getDoc(m.ref)).data();
  assert.equal(inChat.opened, true);
  assert.equal(inChat.url, undefined);
});

test('a file deleted for everyone is archived with its file', async () => {
  const bytes = Buffer.from('quarterly numbers');
  const m = await send(
    { type: 'file', fileName: 'report.txt', fileSize: bytes.length },
    { path: (id) => `chats/${CHAT}/files/${id}/report.txt`, bytes, mimeType: 'text/plain' },
  );
  await client.deleteDoc(m.ref);

  const archived = await waitForArchive(m.id);
  assert.equal(archived.reason, 'deleted');
  assert.ok(archived.deletedAt, 'deletedAt is set');
  assert.equal(archived.fileName, 'report.txt');
  assert.equal(archived.archivePath, `chats/${CHAT}/deleted/${m.id}/report.txt`);
  assert.equal(await fileExists(m.storagePath), false);
  assert.deepEqual((await bucket.file(archived.archivePath).download())[0], bytes);
  assert.equal((await client.getDoc(m.ref)).exists(), false, 'gone from the chat');
});

test('a text message deleted for everyone is archived', async () => {
  const m = await send({ type: 'text', text: 'see you at 7' });
  await client.deleteDoc(m.ref);

  const archived = await waitForArchive(m.id);
  assert.equal(archived.reason, 'deleted');
  assert.equal(archived.text, 'see you at 7');
  assert.equal(archived.archivePath, undefined);
});

test('a view-once photo deleted after opening keeps its archived photo', async () => {
  const m = await sendViewOnce();
  await open(m);
  const first = await waitForArchive(m.id);
  await client.deleteDoc(m.ref);

  const archived = await waitForArchive(m.id, (d) => d.reason === 'deleted');
  assert.equal(archived.archivePath, first.archivePath);
  assert.ok(archived.openedAt && archived.deletedAt);
  assert.equal(await fileExists(archived.archivePath), true);
});

test('read receipts and normal photos do not touch the archive', async () => {
  const m = await send(
    { type: 'image', width: 1, height: 1, viewOnce: false, opened: false },
    { path: (id) => `chats/${CHAT}/images/${id}.png`, bytes: PNG, mimeType: 'image/png' },
  );
  await client.updateDoc(m.ref, { seen: true });
  await new Promise((r) => setTimeout(r, 3000));
  assert.equal((await archiveDoc(m.id).get()).exists, false);
  assert.equal(await fileExists(m.storagePath), true);
});

test('an edited text keeps its previous words in the archive', async () => {
  const m = await send({ type: 'text', text: 'see you at 6' });
  await client.updateDoc(m.ref, {
    text: 'see you at 7',
    edited: true,
    editedAt: client.serverTimestamp(),
  });

  const deadline = Date.now() + 30_000;
  let edits = [];
  while (edits.length === 0 && Date.now() < deadline) {
    const snap = await adminDb
      .collection(`chats/${CHAT}/deleted`)
      .where('messageId', '==', m.id)
      .get();
    edits = snap.docs.map((d) => d.data());
    if (edits.length === 0) await new Promise((r) => setTimeout(r, 250));
  }
  assert.equal(edits.length, 1, 'one archive entry per edit');
  assert.equal(edits[0].reason, 'edited');
  assert.equal(edits[0].text, 'see you at 6');
  assert.equal(edits[0].newText, 'see you at 7');

  const inChat = (await client.getDoc(m.ref)).data();
  assert.equal(inChat.text, 'see you at 7');
  assert.equal(inChat.edited, true);
});

test('a deleted voice message is archived with its audio', async () => {
  const audio = Buffer.from('fake m4a bytes');
  const m = await send(
    { type: 'audio', durationMs: 4200, waveform: [10, 80, 40], played: false },
    { path: (id) => `chats/${CHAT}/audio/${id}.m4a`, bytes: audio, mimeType: 'audio/mp4' },
  );
  await client.deleteDoc(m.ref);

  const archived = await waitForArchive(m.id);
  assert.equal(archived.reason, 'deleted');
  assert.equal(archived.durationMs, 4200);
  assert.equal(archived.archivePath, `chats/${CHAT}/deleted/${m.id}/${m.id}.m4a`);
  assert.deepEqual((await bucket.file(archived.archivePath).download())[0], audio);
  assert.equal(await fileExists(m.storagePath), false);
});

test('reactions, "played" and text edits are allowed; other changes are not', async () => {
  const text = await send({ type: 'text', text: 'hello' });
  await client.updateDoc(text.ref, { 'reactions.p2': '❤️' });
  await client.updateDoc(text.ref, { 'reactions.p1': '😂' });
  await client.updateDoc(text.ref, { 'reactions.p2': client.deleteField() });
  assert.deepEqual((await client.getDoc(text.ref)).data().reactions, { p1: '😂' });
  await assertDenied(client.updateDoc(text.ref, { 'reactions.stranger': '👍' }));
  await assertDenied(client.updateDoc(text.ref, { senderId: 'p2' }));
  await assertDenied(client.updateDoc(text.ref, { type: 'image' }));

  const voice = await send(
    { type: 'audio', durationMs: 1000, waveform: [], played: false },
    { path: (id) => `chats/${CHAT}/audio/${id}.m4a`, bytes: Buffer.from('x'), mimeType: 'audio/mp4' },
  );
  await client.updateDoc(voice.ref, { played: true });
  await assertDenied(client.updateDoc(voice.ref, { text: 'not a text message', edited: true }));
  const object = clientStorage.ref(storage, voice.storagePath);
  assert.deepEqual(Buffer.from(await clientStorage.getBytes(object)), Buffer.from('x'));

  await assertDenied(client.addDoc(messages(), { senderId: 'p1', type: 'video' }));
});

test('the app cannot see or change the archive, or delete files', async () => {
  const m = await sendViewOnce();
  await open(m);
  const { archivePath } = await waitForArchive(m.id);

  const archived = client.doc(db, 'chats', CHAT, 'deleted', m.id);
  await assertDenied(client.getDoc(archived));
  await assertDenied(client.getDocs(client.collection(db, 'chats', CHAT, 'deleted')));
  await assertDenied(client.setDoc(archived, { reason: 'tampered' }));
  await assertDenied(client.deleteDoc(archived));

  await assertDenied(clientStorage.getBytes(clientStorage.ref(storage, archivePath)));
  await assertDenied(clientStorage.deleteObject(clientStorage.ref(storage, archivePath)));
  await assertDenied(
    clientStorage.uploadBytes(clientStorage.ref(storage, `chats/${CHAT}/deleted/x/y.png`), PNG),
  );

  // Photos in the chat can be read but not deleted by the app.
  const photo = await sendViewOnce();
  const object = clientStorage.ref(storage, photo.storagePath);
  assert.deepEqual(Buffer.from(await clientStorage.getBytes(object)), PNG);
  await assertDenied(clientStorage.deleteObject(object));
});
