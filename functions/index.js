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
const logger = require('firebase-functions/logger');
const { notificationFor } = require('./notification');

// Same region as the Firestore database (see firebase.json).
setGlobalOptions({ region: 'asia-south1', maxInstances: 5 });

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
