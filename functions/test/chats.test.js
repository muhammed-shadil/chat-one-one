// The two chats' settings (chats.js). Plain unit tests: no emulators needed.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const {
  FIRST_CHAT,
  SECOND_CHAT,
  ADMIN_SCOPES,
  siteFor,
  chatOfPath,
  scopeIncludesPath,
} = require('../chats');

const root = path.join(__dirname, '..', '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('each chat has its own ID and website', () => {
  assert.notEqual(FIRST_CHAT.id, SECOND_CHAT.id);
  assert.notEqual(FIRST_CHAT.site, SECOND_CHAT.site);
  assert.equal(FIRST_CHAT.site, 'https://chat-one-one-66cbf.web.app');
});

test('the chat IDs match the app and the security rules', () => {
  const config = read('lib/config.dart');
  assert.match(config, new RegExp(`kFirstChatId = '${FIRST_CHAT.id}'`));
  assert.match(config, new RegExp(`kSecondChatId = '${SECOND_CHAT.id}'`));
  for (const rules of ['firestore.rules', 'storage.rules']) {
    assert.match(
      read(rules),
      new RegExp(`chatId in \\['${FIRST_CHAT.id}', '${SECOND_CHAT.id}'\\]`),
      rules,
    );
  }
});

test("each chat's notifications open its own website", () => {
  assert.equal(siteFor(FIRST_CHAT.id), FIRST_CHAT.site);
  assert.equal(siteFor(SECOND_CHAT.id), SECOND_CHAT.site);
  // Anything else keeps opening the first chat's website, as before.
  assert.equal(siteFor('something-else'), FIRST_CHAT.site);
});

test('Storage paths are matched to their chat', () => {
  assert.equal(chatOfPath(`chats/${SECOND_CHAT.id}/images/a.png`), SECOND_CHAT.id);
  assert.equal(chatOfPath(`chats/${FIRST_CHAT.id}/deleted/a/b.png`), FIRST_CHAT.id);
  for (const bad of ['', 'chats/', 'chats//a.png', 'other/x/a.png', undefined, 42]) {
    assert.equal(chatOfPath(bad), null, String(bad));
  }
});

test('the admin pages never overlap', () => {
  const first = `chats/${FIRST_CHAT.id}/images/a.png`;
  const second = `chats/${SECOND_CHAT.id}/images/a.png`;
  const old = 'chats/an-old-chat-id/images/a.png';

  assert.equal(scopeIncludesPath(ADMIN_SCOPES.first, first), true);
  assert.equal(scopeIncludesPath(ADMIN_SCOPES.first, old), true, 'leftovers stay on the first page');
  assert.equal(scopeIncludesPath(ADMIN_SCOPES.first, second), false);

  assert.equal(scopeIncludesPath(ADMIN_SCOPES.second, second), true);
  assert.equal(scopeIncludesPath(ADMIN_SCOPES.second, first), false);
  assert.equal(scopeIncludesPath(ADMIN_SCOPES.second, old), false);

  assert.equal(scopeIncludesPath(ADMIN_SCOPES.first, 'not-in-chats.png'), false);
  assert.ok(second.startsWith(ADMIN_SCOPES.second.storagePrefix));
  assert.ok(first.startsWith(ADMIN_SCOPES.first.storagePrefix));
});
