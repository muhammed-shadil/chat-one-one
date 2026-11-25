// The two chats in this project. They are completely separate: each has its
// own chat ID (kFirstChatId / kSecondChatId in lib/config.dart, also in
// firestore.rules and storage.rules), its own website, and its own admin page
// with its own password.
//
// This file has no Firebase calls, so it can be unit tested without emulators.

const FIRST_CHAT = {
  id: 'rhxd7yqwcq6xant5r6k5nzvx',
  site: 'https://chat-one-one-66cbf.web.app',
};

const SECOND_CHAT = {
  id: '4drjzcca8t69rrduir7z2hnk',
  site: 'https://chat-one-one-2-xevg3.web.app',
};

// The website a chat's push notifications open.
function siteFor(chatId) {
  return chatId === SECOND_CHAT.id ? SECOND_CHAT.site : FIRST_CHAT.site;
}

// The chat ID of a Storage path, chats/{chatId}/…, or null.
function chatOfPath(path) {
  const m = typeof path === 'string' ? path.match(/^chats\/([^/]+)\//) : null;
  return m ? m[1] : null;
}

// Which chats an admin page may show.
//
// The second chat's page shows only the second chat. The first chat's page
// shows every chat in the project except the second, which is exactly what
// it showed before the second chat existed (leftovers from an old chat ID
// included).
const ADMIN_SCOPES = {
  first: {
    storagePrefix: 'chats/',
    includes: (chatId) => typeof chatId === 'string' && chatId !== SECOND_CHAT.id,
  },
  second: {
    storagePrefix: `chats/${SECOND_CHAT.id}/`,
    includes: (chatId) => chatId === SECOND_CHAT.id,
  },
};

// Whether a stored file belongs to one of the chats a scope shows.
function scopeIncludesPath(scope, path) {
  return scope.includes(chatOfPath(path));
}

module.exports = {
  FIRST_CHAT,
  SECOND_CHAT,
  ADMIN_SCOPES,
  siteFor,
  chatOfPath,
  scopeIncludesPath,
};
