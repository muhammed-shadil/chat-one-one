// Server-side work for the chat:
//
// 1. A private archive of everything that disappears from the chat. The app
//    never deletes photos or files itself. When a view-once photo is opened,
//    a message is deleted for everyone, or a text is edited, the chat looks
//    exactly as before ("Opened", the message is gone, "edited"), and these
//    functions keep the old data aside:
//      Firestore: chats/{chatId}/deleted/{messageId}   the message, plus why
//                 chats/{chatId}/deleted/{messageId}_edit_{eventId}   old text
//      Storage:   chats/{chatId}/deleted/{messageId}/  the photo, file or audio
//    The security rules hide the archive from the app, so it can only be seen
//    in the Firebase console.
//
// 2. Push notifications for new messages (notifyNewMessage).
//
// 3. The password-protected admin page on the website, /admin/photos, which
//    shows every photo, archived ones included (adminPhotos, adminPhoto; see
//    admin.js).

const { pipeline } = require('node:stream/promises');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getStorage } = require('firebase-admin/storage');
const { setGlobalOptions } = require('firebase-functions/v2');
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} = require('firebase-functions/v2/firestore');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const { notificationFor } = require('./notification');
const {
  passwordIsSetUp,
  passwordMatches,
  linkSigner,
  linkExpiry,
  photoLink,
  buildPhotoList,
} = require('./admin');

// Same region as the Firestore database (see firebase.json).
const REGION = 'asia-south1';
setGlobalOptions({ region: REGION, maxInstances: 5 });

// Set with `firebase functions:secrets:set ADMIN_PASSWORD`; for the
// emulators, in functions/.secret.local. At least 12 characters.
const ADMIN_PASSWORD = defineSecret('ADMIN_PASSWORD');

initializeApp();

// The project's Storage bucket, as in lib/firebase_options.dart.
const BUCKET = 'chat-one-one-66cbf.firebasestorage.app';

const MESSAGE = 'chats/{chatId}/messages/{messageId}';

exports.archiveOpenedViewOnce = onDocumentUpdated(MESSAGE, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after.viewOnce || before.opened || !after.opened) return;

  const { chatId, messageId } = event.params;
  await archive(chatId, messageId, after, { reason: 'view_once_opened' });
});

exports.archiveDeletedMessage = onDocumentDeleted(MESSAGE, async (event) => {
  const { chatId, messageId } = event.params;
  await archive(chatId, messageId, event.data.data(), {
    reason: 'deleted',
    deletedAt: FieldValue.serverTimestamp(),
  });
});

// Keeps the words a message had before each edit.
exports.archiveEditedMessage = onDocumentUpdated(MESSAGE, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after.edited || before.text === after.text) return;

  const { chatId, messageId } = event.params;
  // The event ID makes a retried delivery overwrite, not duplicate, the entry.
  await getFirestore()
    .doc(`chats/${chatId}/deleted/${messageId}_edit_${event.id}`)
    .set({
      ...before,
      messageId,
      reason: 'edited',
      newText: after.text,
      editedAt: FieldValue.serverTimestamp(),
    });
  logger.info(`Archived the previous text of ${messageId}`);
});

const SITE = 'https://chat-one-one-66cbf.web.app';

// Errors meaning a token belongs to an uninstalled app or a browser that
// turned notifications off, so it should be forgotten.
const DEAD_TOKEN = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

exports.notifyNewMessage = onDocumentCreated(MESSAGE, async (event) => {
  const message = event.data.data();
  const { chatId } = event.params;
  const members = getFirestore().collection(`chats/${chatId}/members`);
  const recipientId = message.senderId === 'p1' ? 'p2' : 'p1';
  const [sender, recipient] = await Promise.all([
    members.doc(message.senderId).get(),
    members.doc(recipientId).get(),
  ]);
  const tokens = recipient.get('pushTokens') || [];
  if (tokens.length === 0) return;

  const { title, body } = notificationFor(message, sender.get('name'));
  const result = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    android: { priority: 'high', notification: { channelId: 'messages' } },
    webpush: {
      notification: { icon: `${SITE}/icons/Icon-192.png` },
      fcmOptions: { link: SITE },
    },
  });

  const dead = tokens.filter((_, i) => DEAD_TOKEN.has(result.responses[i].error?.code));
  if (dead.length) {
    await recipient.ref.update({ pushTokens: FieldValue.arrayRemove(...dead) });
  }
  logger.info(`Notified ${recipientId}: ${result.successCount} sent, ${dead.length} stale`);
});

// ------------------------------------------------------------- admin page

// Lists every photo for the admin page, given the admin password.
exports.adminPhotos = onCall({ secrets: [ADMIN_PASSWORD] }, async (request) => {
  const password = ADMIN_PASSWORD.value();
  if (!passwordIsSetUp(password)) {
    throw new HttpsError('failed-precondition', 'The admin password has not been set up yet.');
  }
  if (!passwordMatches(request.data?.password, password)) {
    logger.warn('Admin page: wrong password');
    // Slows down guessing.
    await new Promise((resolve) => setTimeout(resolve, 1000));
    throw new HttpsError('permission-denied', 'Wrong password.');
  }

  const db = getFirestore();
  const [chatRefs, [files]] = await Promise.all([
    // Includes chats that only have subcollections and no document of their own.
    db.collection('chats').listDocuments(),
    getStorage().bucket(BUCKET).getFiles({ prefix: 'chats/' }),
  ]);
  const photoTypes = ['image', 'file'];
  const chats = await Promise.all(
    chatRefs.map(async (chat) => {
      const [messages, archived, members] = await Promise.all([
        chat.collection('messages').where('type', 'in', photoTypes).get(),
        chat.collection('deleted').where('type', 'in', photoTypes).get(),
        chat.collection('members').get(),
      ]);
      const entries = (snap) => snap.docs.map((d) => ({ id: d.id, data: d.data() }));
      return {
        id: chat.id,
        members: Object.fromEntries(members.docs.map((d) => [d.id, { name: d.get('name') }])),
        messages: entries(messages),
        archived: entries(archived),
      };
    }),
  );

  const exp = linkExpiry(Date.now());
  const signer = linkSigner(password);
  const base = adminPhotoUrl();
  const result = buildPhotoList(
    chats,
    files.map((f) => ({
      path: f.name,
      size: f.metadata.size,
      contentType: f.metadata.contentType,
      timeCreated: f.metadata.timeCreated,
    })),
    (path) => photoLink(base, signer, path, exp),
  );
  logger.info(`Admin page: listed ${result.photos.length} photos`);
  return { ...result, linksExpireAt: exp * 1000 };
});

// Sends one photo to the admin page, through a signed link from adminPhotos.
exports.adminPhoto = onRequest({ secrets: [ADMIN_PASSWORD] }, async (req, res) => {
  // The link itself is the permission, so any page may load it. This lets
  // the website draw the photo itself instead of using an <img> element.
  res.set('Access-Control-Allow-Origin', '*');
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.status(405).send('Method not allowed');
    return;
  }
  const password = ADMIN_PASSWORD.value();
  const { path, exp, sig } = req.query;
  if (!passwordIsSetUp(password) || !linkSigner(password).verify(path, exp, sig)) {
    res.status(403).send('This link is not valid.');
    return;
  }
  const secondsLeft = Number(exp) - Math.floor(Date.now() / 1000);
  if (!(secondsLeft > 0)) {
    res.status(403).send('This link has expired. Reload the admin page.');
    return;
  }

  const file = getStorage().bucket(BUCKET).file(path);
  let metadata;
  try {
    [metadata] = await file.getMetadata();
  } catch (e) {
    if (e.code !== 404) throw e;
    res.status(404).send('This photo is no longer in Storage.');
    return;
  }
  if (!String(metadata.contentType).startsWith('image/')) {
    res.status(415).send('Not a photo.');
    return;
  }
  res.set({
    'Content-Type': metadata.contentType,
    'Content-Length': String(metadata.size),
    'Cache-Control': `private, max-age=${secondsLeft}`,
    'X-Content-Type-Options': 'nosniff',
    // Opened on its own, the file can't run anything (an SVG with scripts).
    'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; sandbox",
  });
  if (req.method === 'HEAD') {
    res.end();
    return;
  }
  await pipeline(file.createReadStream(), res);
});

// Where adminPhoto is reachable, on the emulators or the real project.
function adminPhotoUrl() {
  const project = process.env.GCLOUD_PROJECT || 'chat-one-one-66cbf';
  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    return `http://127.0.0.1:5001/${project}/${REGION}/adminPhoto`;
  }
  return `https://${REGION}-${project}.cloudfunctions.net/adminPhoto`;
}

// ------------------------------------------------------------------ archive

async function archive(chatId, messageId, message, extra) {
  // The download link stops working once the file is moved, so drop it.
  const { url, ...data } = message;
  const archivePath = await moveFile(chatId, messageId, data.storagePath);
  await getFirestore()
    .doc(`chats/${chatId}/deleted/${messageId}`)
    // Merge: a view-once photo that is opened and later deleted keeps
    // its first archive entry and gains the deletion details.
    .set({ ...data, ...extra, ...(archivePath && { archivePath }) }, { merge: true });
  logger.info(`Archived ${messageId} (${extra.reason})`, { archivePath });
}

// Moves a photo or file into the deleted folder and returns its new path,
// or null if the message had no file or it was already gone.
async function moveFile(chatId, messageId, storagePath) {
  if (!storagePath) return null;
  const bucket = getStorage().bucket(BUCKET);
  const name = storagePath.split('/').pop();
  const archivePath = `chats/${chatId}/deleted/${messageId}/${name}`;
  const source = bucket.file(storagePath);
  const target = bucket.file(archivePath);

  try {
    await source.copy(target);
  } catch (e) {
    if (e.code !== 404) throw e;
    // Already moved (e.g. a view-once photo deleted after it was opened).
    const [exists] = await target.exists();
    if (!exists) logger.warn(`File for ${messageId} was missing: ${storagePath}`);
    return exists ? archivePath : null;
  }
  // The copy keeps the original's download token, which would let the old
  // link open the archived file. Remove it so only the console can open it.
  await target.setMetadata({ metadata: { firebaseStorageDownloadTokens: null } });
  await source.delete({ ignoreNotFound: true });
  return archivePath;
}
