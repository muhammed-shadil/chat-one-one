// The private admin page on the website (/admin/photos) shows every photo
// the chat has ever held: the ones still in the chat, view-once photos
// (waiting or opened), photos deleted for everyone, and image files in
// Storage that no message points to. The archive is hidden from the app by
// the security rules, so the page gets everything through two functions in
// index.js, both locked by the ADMIN_PASSWORD secret:
//
//   adminPhotos  (callable)  password in, list of photos out
//   adminPhoto   (HTTP GET)  one photo, through a signed link from the list
//
// Signed links expire after one to two hours, and the archived files keep
// having no download token, so nothing new can open them from outside.
//
// This file has no Firebase calls, so it can be unit tested without emulators.

const { createHash, createHmac, timingSafeEqual } = require('node:crypto');

// Shorter passwords are refused, so the page can't be opened by guessing.
const MIN_PASSWORD_LENGTH = 12;

function passwordIsSetUp(expected) {
  return typeof expected === 'string' && expected.length >= MIN_PASSWORD_LENGTH;
}

function passwordMatches(given, expected) {
  if (typeof given !== 'string' || !passwordIsSetUp(expected)) return false;
  // Compare digests, which have equal length, in constant time.
  const digest = (s) => createHash('sha256').update(s, 'utf8').digest();
  return timingSafeEqual(digest(given), digest(expected));
}

// Signs and checks photo links with a key derived from the admin password,
// so changing the password also cancels every link handed out before.
function linkSigner(password) {
  const key = createHmac('sha256', String(password)).update('admin photo links').digest();
  const sign = (path, exp) =>
    createHmac('sha256', key).update(`${path}\n${exp}`).digest('base64url');
  return {
    sign,
    verify(path, exp, sig) {
      if (![path, exp, sig].every((v) => typeof v === 'string')) return false;
      const expected = Buffer.from(sign(path, exp));
      const given = Buffer.from(sig);
      return given.length === expected.length && timingSafeEqual(given, expected);
    },
  };
}

const HOUR = 3600;

// When links made at [nowMs] stop working, in seconds. Links stay the same
// for a whole hour, so the browser can reuse what it already downloaded, and
// always last at least one more hour.
function linkExpiry(nowMs) {
  return (Math.floor(nowMs / 1000 / HOUR) + 2) * HOUR;
}

function photoLink(base, signer, path, exp) {
  const query = new URLSearchParams({ path, exp: String(exp), sig: signer.sign(path, exp) });
  return `${base}?${query}`;
}

// Photos are image messages, and files sent with an image type (a .jpg
// picked as a file).
function isPhoto(data) {
  return (
    data.type === 'image' ||
    (data.type === 'file' && typeof data.mimeType === 'string' && data.mimeType.startsWith('image/'))
  );
}

const isImageFile = (file) => typeof file.contentType === 'string' && file.contentType.startsWith('image/');

const millis = (timestamp) =>
  timestamp && typeof timestamp.toMillis === 'function' ? timestamp.toMillis() : null;

// Builds what the admin page shows.
//
//   chats  [{ id, members: { p1: {name}, … }, messages: [{ id, data }],
//            archived: [{ id, data }] }]   from chats/{id}/messages and /deleted
//   files  [{ path, size, contentType, timeCreated }]   everything in Storage under chats/
//   link   (path) => signed URL for one stored file
//
// Each photo gets a status:
//   chat         still in the chat
//   view_once    view-once photo not opened yet
//   opened       view-once photo that was opened (now in the archive)
//   deleted      deleted for everyone (now in the archive)
//   unlinked     image in Storage that no message or archive entry points to
function buildPhotoList(chats, files, link) {
  const stored = new Map(files.map((f) => [f.path, f]));
  const linked = new Set();
  const photos = [];

  // The first of [paths] that is in Storage, else the first one given.
  const pick = (...paths) => {
    const candidates = paths.filter(Boolean);
    return candidates.find((p) => stored.has(p)) ?? candidates[0] ?? null;
  };

  const add = (chatId, messageId, data, status, path) => {
    const file = path ? stored.get(path) : undefined;
    if (path) linked.add(path);
    photos.push({
      key: `${chatId}/${messageId}`,
      chatId,
      messageId,
      senderId: typeof data.senderId === 'string' ? data.senderId : null,
      status,
      viewOnce: data.viewOnce === true,
      caption: typeof data.text === 'string' && data.text ? data.text : null,
      fileName: typeof data.fileName === 'string' ? data.fileName : null,
      sentAt: millis(data.createdAt),
      openedAt: millis(data.openedAt),
      deletedAt: millis(data.deletedAt),
      width: typeof data.width === 'number' ? data.width : null,
      height: typeof data.height === 'number' ? data.height : null,
      size: file ? Number(file.size) : null,
      path,
      // Null when the file is gone, so the page can say so.
      url: file ? link(path) : null,
    });
  };

  for (const chat of chats) {
    const archivedIds = new Set();
    for (const { id, data } of chat.archived) {
      if (!isPhoto(data)) continue; // edited texts and other messages
      archivedIds.add(id);
      const status = data.reason === 'deleted' ? 'deleted' : 'opened';
      add(chat.id, id, data, status, pick(data.archivePath, data.storagePath));
    }
    for (const { id, data } of chat.messages) {
      // An opened view-once photo stays in the chat as "Opened"; its archive
      // entry above already shows it.
      if (!isPhoto(data) || archivedIds.has(id)) continue;
      const status = !data.viewOnce ? 'chat' : data.opened ? 'opened' : 'view_once';
      add(chat.id, id, data, status, pick(data.storagePath));
    }
  }

  for (const file of files) {
    if (linked.has(file.path) || !isImageFile(file)) continue;
    // chats/{chatId}/{folder}/{messageId}.{ext} or …/{messageId}/{name}
    const [, chatId = '', , rest = ''] = file.path.split('/');
    const messageId = rest.replace(/\.[^.]*$/, '');
    const created = Date.parse(file.timeCreated);
    photos.push({
      key: file.path,
      chatId,
      messageId: messageId || null,
      senderId: null,
      status: 'unlinked',
      viewOnce: false,
      caption: null,
      fileName: file.path.split('/').pop(),
      sentAt: Number.isNaN(created) ? null : created,
      openedAt: null,
      deletedAt: null,
      width: null,
      height: null,
      size: Number(file.size),
      path: file.path,
      url: link(file.path),
    });
  }

  photos.sort((a, b) => (b.sentAt ?? b.deletedAt ?? 0) - (a.sentAt ?? a.deletedAt ?? 0));

  // Every chat with members or photos, with the names the two people chose.
  const chatIds = new Set([...chats.map((c) => c.id), ...photos.map((p) => p.chatId)]);
  const membersOf = new Map(chats.map((c) => [c.id, c.members]));
  const chatList = [...chatIds].map((id) => {
    const names = {};
    for (const [person, member] of Object.entries(membersOf.get(id) ?? {})) {
      if (typeof member?.name === 'string' && member.name) names[person] = member.name;
    }
    return { id, names, photoCount: photos.filter((p) => p.chatId === id).length };
  });

  return { chats: chatList, photos };
}

module.exports = {
  MIN_PASSWORD_LENGTH,
  passwordIsSetUp,
  passwordMatches,
  linkSigner,
  linkExpiry,
  photoLink,
  isPhoto,
  buildPhotoList,
};
