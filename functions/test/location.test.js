// Security rules for shared locations, run against the local emulators with
// `npm test` (never the real project).
//
// The app's side is played by the Firebase JS client SDK, so the rules apply
// exactly as they do to the phones and the website. The Admin SDK, which
// skips the rules, sets things up and checks what was really stored.

const assert = require('node:assert/strict');
const { test, before, after, beforeEach } = require('node:test');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('Run these tests with `npm test`, which starts the emulators.');
}

const admin = require('firebase-admin/app');
const { getFirestore, Timestamp: AdminTimestamp } = require('firebase-admin/firestore');
const { initializeApp, deleteApp } = require('firebase/app');
const client = require('firebase/firestore');

const PROJECT = 'chat-one-one-66cbf';
const CHAT = 'rhxd7yqwcq6xant5r6k5nzvx'; // kChatId in lib/config.dart
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

let app, db, adminDb;

before(() => {
  admin.initializeApp({ projectId: PROJECT });
  adminDb = getFirestore();

  app = initializeApp({ projectId: PROJECT, apiKey: 'test' });
  db = client.getFirestore(app);
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  client.connectFirestoreEmulator(db, host, Number(port));
});

after(async () => {
  await client.terminate(db);
  await deleteApp(app);
});

const stored = (personId) => adminDb.doc(`chats/${CHAT}/locations/${personId}`);

// Every test starts with nobody's location shared.
beforeEach(() => Promise.all(['p1', 'p2'].map((p) => stored(p).delete())));

// ------------------------------------------------------------------ helpers

const locationDoc = (personId, chat = CHAT) =>
  client.doc(db, 'chats', chat, 'locations', personId);

// What shareLocation in lib/services/chat_service.dart writes.
function location(personId, changes = {}) {
  const now = Date.now();
  return {
    userId: personId,
    latitude: 12.971599,
    longitude: 77.594566,
    accuracy: 14.2,
    capturedAt: client.Timestamp.fromMillis(now - 2000),
    sharedAt: client.serverTimestamp(),
    expiresAt: client.Timestamp.fromMillis(now + 7 * DAY),
    sharingType: 'one_time',
    ...changes,
  };
}

const share = (personId, changes) =>
  client.setDoc(locationDoc(personId), location(personId, changes));

async function assertDenied(promise, what) {
  await assert.rejects(
    promise,
    (e) => /permission|unauthorized/i.test(`${e.code} ${e.message}`),
    `should be refused: ${what}`,
  );
}

// -------------------------------------------------------------------- tests

test('a location shared once is stored as sent and the other person can read it', async () => {
  await share('p2');

  const snap = await client.getDoc(locationDoc('p2'));
  const d = snap.data();
  assert.equal(d.userId, 'p2');
  assert.equal(d.latitude, 12.971599);
  assert.equal(d.longitude, 77.594566);
  assert.equal(d.accuracy, 14.2);
  assert.equal(d.sharingType, 'one_time');
  assert.ok(d.capturedAt instanceof client.Timestamp);
  assert.ok(d.sharedAt instanceof client.Timestamp, 'server time is filled in');
});

test('sharing again replaces the earlier location instead of adding another', async () => {
  await share('p2', { latitude: 10 });
  await share('p2', { latitude: 11 });

  const all = await adminDb.collection(`chats/${CHAT}/locations`).get();
  assert.equal(all.size, 1);
  assert.equal(all.docs[0].get('latitude'), 11);
});

test('impossible coordinates and accuracies are refused', async () => {
  for (const bad of [
    { latitude: 90.0001 },
    { latitude: -91 },
    { longitude: 180.5 },
    { longitude: -181 },
    { latitude: NaN },
    { longitude: Infinity },
    { latitude: '12.97' },
    { accuracy: -1 },
    { accuracy: 100001 },
    { accuracy: null },
  ]) {
    await assertDenied(share('p1', bad), JSON.stringify(bad, (_, v) => (Number.isNaN(v) ? 'NaN' : v)));
  }
  assert.equal((await stored('p1').get()).exists, false);
});

test('only the right shape is accepted: owner, type, timestamps, fields', async () => {
  const now = Date.now();
  await assertDenied(share('p1', { userId: 'p2' }), "someone else's ID");
  await assertDenied(share('p1', { sharingType: 'continuous' }), 'not one-time');
  await assertDenied(share('p1', { speed: 3 }), 'an extra field');
  await assertDenied(
    share('p1', { sharedAt: client.Timestamp.fromMillis(now - DAY) }),
    'sharedAt not set by the server',
  );
  await assertDenied(
    share('p1', { expiresAt: client.Timestamp.fromMillis(now + 31 * DAY) }),
    'kept longer than 30 days',
  );
  await assertDenied(
    share('p1', { expiresAt: client.Timestamp.fromMillis(now - 1000) }),
    'already expired',
  );
  await assertDenied(
    share('p1', { capturedAt: client.Timestamp.fromMillis(now + 2 * HOUR) }),
    'captured in the future',
  );
  const { accuracy, ...missing } = location('p1');
  await assertDenied(client.setDoc(locationDoc('p1'), missing), 'a missing field');
  await assertDenied(client.setDoc(locationDoc('p3'), location('p3')), 'not one of the two people');

  // Partial updates are held to the same rules.
  await share('p1');
  await assertDenied(client.updateDoc(locationDoc('p1'), { latitude: 95 }), 'an update to 95°');
});

test('locations cannot be listed, or reached under another chat ID', async () => {
  await share('p1');
  await assertDenied(
    client.getDocs(client.collection(db, 'chats', CHAT, 'locations')),
    'listing',
  );
  await assertDenied(
    client.getDocs(client.collectionGroup(db, 'locations')),
    'listing across chats',
  );
  await assertDenied(client.getDoc(locationDoc('p1', 'some-other-chat')), 'another chat');
  await assertDenied(
    client.setDoc(locationDoc('p1', 'some-other-chat'), location('p1')),
    'writing to another chat',
  );
  await assertDenied(client.getDoc(locationDoc('p3')), 'someone else');
});

test('an expired location is hidden, and can still be deleted', async () => {
  // As if it had been shared eight days ago, with the one-week retention.
  await stored('p2').set({
    userId: 'p2',
    latitude: 12.97,
    longitude: 77.59,
    accuracy: 10,
    capturedAt: AdminTimestamp.fromMillis(Date.now() - 8 * DAY),
    sharedAt: AdminTimestamp.fromMillis(Date.now() - 8 * DAY),
    expiresAt: AdminTimestamp.fromMillis(Date.now() - DAY),
    sharingType: 'one_time',
  });

  await assertDenied(client.getDoc(locationDoc('p2')), 'reading an expired location');
  await client.deleteDoc(locationDoc('p2'));
  assert.equal((await stored('p2').get()).exists, false);
});

test('a shared location can be deleted for good, and nothing is archived', async () => {
  await share('p2');
  await client.deleteDoc(locationDoc('p2'));

  assert.equal((await stored('p2').get()).exists, false);
  assert.equal((await adminDb.doc(`chats/${CHAT}/deleted/p2`).get()).exists, false);
  // Looking up a location nobody has shared finds nothing, without an error.
  assert.equal((await client.getDoc(locationDoc('p2'))).exists(), false);
});
