// The emulators read ADMIN_PASSWORD and ADMIN_PASSWORD_2 from
// functions/.secret.local. If one is missing there, they ask the real
// project's Secret Manager instead, so `npm test` first makes sure the file
// has both. The file is kept out of git
// (*.local) and is never deployed.
//
// Run directly (`node test/local-secret.js`) to create it if needed.

const fs = require('node:fs');
const path = require('node:path');
const { randomBytes } = require('node:crypto');

const FILE = path.join(__dirname, '..', '.secret.local');

function readLocalSecrets() {
  let text;
  try {
    text = fs.readFileSync(FILE, 'utf8');
  } catch (e) {
    if (e.code === 'ENOENT') return {};
    throw e;
  }
  const secrets = {};
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m) secrets[m[1]] = m[2].replace(/^(['"])(.*)\1$/, '$2');
  }
  return secrets;
}

// One password per chat's admin page (see functions/chats.js).
const SECRETS = ['ADMIN_PASSWORD', 'ADMIN_PASSWORD_2'];

function ensureAdminPassword() {
  for (const name of SECRETS) {
    if (readLocalSecrets()[name]) continue;
    const existing = fs.existsSync(FILE) ? fs.readFileSync(FILE, 'utf8') : '';
    const newline = existing && !existing.endsWith('\n') ? '\n' : '';
    fs.appendFileSync(FILE, `${newline}${name}=${randomBytes(18).toString('base64url')}\n`);
    console.log(`Added an emulator-only ${name} to ${FILE}`);
  }
}

if (require.main === module) ensureAdminPassword();

module.exports = { readLocalSecrets };
