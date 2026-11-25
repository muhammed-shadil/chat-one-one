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
//    shows every photo, archived ones included (see admin.js). Each chat has
//    its own pair of functions and its own password, and only ever sees its
//    own photos (see chats.js):
//      first chat:   adminPhotos,  adminPhoto    ADMIN_PASSWORD
//      second chat:  adminPhotos2, adminPhoto2   ADMIN_PASSWORD_2
//
// The two chats share the archive and notification functions: those work on
// whichever chat a message is in (the {chatId} in the path).

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
const { ADMIN_SCOPES, siteFor, scopeIncludesPath } = require('./chats');

// Same region as the Firestore database (see firebase.json).
const REGION = 'asia-south1';
setGlobalOptions({ region: REGION, maxInstances: 5 });

// Set with `firebase functions:secrets:set ADMIN_PASSWORD` (first chat) and
// `… ADMIN_PASSWORD_2` (second chat); for the emulators, in
// functions/.secret.local. At least 12 characters each.
const ADMIN_PASSWORD = defineSecret('ADMIN_PASSWORD');
const ADMIN_PASSWORD_2 = defineSecret('ADMIN_PASSWORD_2');

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
  // Each chat's notifications open that chat's own website.
  const site = siteFor(chatId);
  const result = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    android: { priority: 'high', notification: { channelId: 'messages' } },
    webpush: {
      notification: { icon: `${site}/icons/Icon-192.png` },
      fcmOptions: { link: site },
    },
  });

  const dead = tokens.filter((_, i) => DEAD_TOKEN.has(result.responses[i].error?.code));
  if (dead.length) {
    await recipient.ref.update({ pushTokens: FieldValue.arrayRemove(...dead) });
  }
  logger.info(`Notified ${recipientId}: ${result.successCount} sent, ${dead.length} stale`);
});

// ------------------------------------------------------------- admin page

// One chat's admin page: [listPhotos] lists its photos given the password,
// and [sendPhoto] sends one photo through a signed link from that list.
// [scope] (chats.js) keeps each page to its own chat's photos, and each page
// signs its links with its own password, so neither page can open the other
// chat's photos.
function adminPage({ label, secret, scope, photoFunction }) {
  const listPhotos = onCall({ secrets: [secret] }, async (request) => {
    const password = secret.value();
    if (!passwordIsSetUp(password)) {
      throw new HttpsError('failed-precondition', 'The admin password has not been set up yet.');
    }
    if (!passwordMatches(request.data?.password, password)) {
      logger.warn(`Admin page (${label}): wrong password`);
      // Slows down guessing.
      await new Promise((resolve) => setTimeout(resolve, 1000));
      throw new HttpsError('permission-denied', 'Wrong password.');
    }

    const db = getFirestore();
    const [allChatRefs, [allFiles]] = await Promise.all([
      // Includes chats that only have subcollections and no document of their own.
      db.collection('chats').listDocuments(),
      getStorage().bucket(BUCKET).getFiles({ prefix: scope.storagePrefix }),
    ]);
    // Only this page's chats, never the other chat's.
    const chatRefs = allChatRefs.filter((chat) => scope.includes(chat.id));
    const files = allFiles.filter((f) => scopeIncludesPath(scope, f.name));
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
    const base = functionUrl(photoFunction);
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
    logger.info(`Admin page (${label}): listed ${result.photos.length} photos`);
    return { ...result, linksExpireAt: exp * 1000 };
  });

  const sendPhoto = onRequest({ secrets: [secret] }, async (req, res) => {
    // The link itself is the permission, so any page may load it. This lets
    // the website draw the photo itself instead of using an <img> element.
    res.set('Access-Control-Allow-Origin', '*');
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.status(405).send('Method not allowed');
      return;
    }
    const password = secret.value();
    const { path, exp, sig } = req.query;
    if (
      !passwordIsSetUp(password) ||
      !linkSigner(password).verify(path, exp, sig) ||
      !scopeIncludesPath(scope, path)
    ) {
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

  return { listPhotos, sendPhoto };
}

// The first chat's admin page, https://chat-one-one-66cbf.web.app/admin/photos
const firstAdmin = adminPage({
  label: 'first chat',
  secret: ADMIN_PASSWORD,
  scope: ADMIN_SCOPES.first,
  photoFunction: 'adminPhoto',
});
exports.adminPhotos = firstAdmin.listPhotos;
exports.adminPhoto = firstAdmin.sendPhoto;

// The second chat's admin page, https://chat-one-one-2-xevg3.web.app/admin/photos
const secondAdmin = adminPage({
  label: 'second chat',
  secret: ADMIN_PASSWORD_2,
  scope: ADMIN_SCOPES.second,
  photoFunction: 'adminPhoto2',
});
exports.adminPhotos2 = secondAdmin.listPhotos;
exports.adminPhoto2 = secondAdmin.sendPhoto;

// Where an HTTP function is reachable, on the emulators or the real project.
function functionUrl(name) {
  const project = process.env.GCLOUD_PROJECT || 'chat-one-one-66cbf';
  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    return `http://127.0.0.1:5001/${project}/${REGION}/${name}`;
  }
  return `https://${REGION}-${project}.cloudfunctions.net/${name}`;
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
