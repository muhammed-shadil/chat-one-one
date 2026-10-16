# Chat One One

A private chat app for exactly two people. There's no login or sign-up: on first
launch, each phone picks **Person 1** or **Person 2** and enters a name, and that's it.

## Features

- Text messages, with sent ✓ and seen ✓✓ (blue) ticks
- Photos from the camera or gallery, with an optional caption
- **View once** photos: the receiver can open them a single time. As soon as
  it's opened the photo leaves the chat and moves to the private
  [archive](#archive-of-opened-deleted-and-edited-messages), and screenshots are
  blocked on Android while it's on screen.
- Files of any type (PDF, DOC, ZIP, APK, …) up to 100 MB. Tap a file to download and open it.
- **Voice messages:** tap the mic to record, then send or delete. They play
  with a waveform you can tap or drag to seek, at 1×, 1.5× or 2×. The mic
  turns blue once the other person has listened.
- **Replies:** swipe a message to the right, or long-press → Reply. Tap the
  quote to jump to the original.
- **Reactions:** long-press → ❤️ 😂 😮 😢 🙏 👍. Pick it again to remove it.
- **Edit** your own texts (long-press → Edit). They show "edited", and the old
  words are kept in the archive.
- Links in messages open in the browser
- **Push notifications** for new messages on Android and the website, with a
  preview ("📷 Photo", "🎤 Voice message (0:12)"; view once photos never show)
- Online status, "typing…", "recording audio…" and "last seen"
- Date separators, and older messages load as you scroll up
- Long-press a message to copy it, or to delete your own message for everyone
  (a copy is kept in the archive)
- On the website, Enter sends and Shift+Enter starts a new line
- **Chat themes:** menu → Chat theme. Six color themes (Classic green, Ocean
  blue, Lavender, Rose, Sunset, Midnight), each in Light, Dark or follow the
  system. Saved per device, so each person picks their own.
- Messages still show offline (Firestore cache)

## What's required

| Item | Why |
|---|---|
| Flutter SDK (3.41+) | to build the app |
| A Firebase project | backend |
| **Cloud Firestore** | stores messages, names, and online status |
| **Cloud Storage for Firebase** | stores photos, files and voice messages |
| **Cloud Functions** | keeps the archive, and sends push notifications |
| **Blaze (pay-as-you-go) plan** | Google requires it to enable Cloud Storage and Cloud Functions. Two people chatting stay inside the free quota (5 GB stored, 1 GB downloaded per day, 50k Firestore reads per day), so the expected cost is ₹0. Set a budget alert to be safe. |
| Two Android phones | iPhone works too, but it has to be built on a Mac |

## Setup

1. **Create a Firebase project** at <https://console.firebase.google.com>, or run
   `firebase projects:create`.
2. **Firestore:** in the console, go to *Build → Firestore Database → Create database* and pick a nearby region (e.g. `asia-south1`).
3. **Storage:** go to *Build → Storage → Get started*. The console asks you to upgrade to Blaze here.
4. **Connect the app** (this generates `lib/firebase_options.dart`):
   ```sh
   flutterfire configure --project=<your-project-id> --platforms=android,ios
   ```
5. **Deploy the security rules and the Cloud Functions:**
   ```sh
   cd functions && npm install && cd ..
   firebase deploy --only firestore:rules,storage,functions --project <your-project-id>
   ```
   The first functions deploy can fail while Google finishes setting up
   Eventarc; wait a few minutes and run it again.
6. **Build and install** on both phones:
   ```sh
   flutter build apk --release
   # output: build/app/outputs/flutter-apk/app-release.apk
   ```
7. Open the app on each phone. One person picks **Person 1** and the other picks **Person 2**.

## Web version

The same app runs in the browser at <https://chat-one-one-66cbf.web.app>
(Firebase Hosting), using the same Firestore and Storage as the phones.
To publish changes:

```sh
flutter build web --release
firebase deploy --only hosting --project chat-one-one-66cbf
```

If a new plugin doesn't work on the website after `flutter pub add`, delete
`.dart_tool/flutter_build` and build again: Flutter can keep using an old list
of web plugins.

In the browser, files open in a new tab instead of being saved in the app, and
screenshots can't be blocked for view once photos.

## Push notifications

When a message arrives, the `notifyNewMessage` Cloud Function sends a
notification to every phone and browser the other person has opened the chat
on. The app asks for permission the first time the chat opens, and saves this
device's token in `members/<p1|p2>.pushTokens`. Tokens of uninstalled apps are
removed automatically. Tapping a notification opens the app or the website.

- **Android:** works with the APK. Android 13+ asks "Allow notifications?".
- **Website:** works in Chrome, Edge and Firefox, using
  `web/firebase-messaging-sw.js`. On iPhone, Safari only allows it once the site
  is added to the Home Screen.
- **iPhone app:** needs an APNs key from an Apple developer account, uploaded in
  the Firebase console under *Project settings → Cloud Messaging*.

## Archive of opened, deleted and edited messages

Nothing that leaves the chat is thrown away. When a view once photo is opened,
a message is deleted for everyone, or a text is edited, the chat looks the same
as always ("Opened", the message disappears, "edited"), and Cloud Functions in
`functions/index.js` keep the old data aside:

| Where | What's kept |
|---|---|
| Firestore `chats/<chat ID>/deleted/<message ID>` | the whole message, plus `reason` (`view_once_opened` or `deleted`), `openedAt` / `deletedAt`, and `archivePath` |
| Firestore `chats/<chat ID>/deleted/<message ID>_edit_<…>` | the text before an edit (`reason: edited`), with `newText` and `editedAt` |
| Storage `chats/<chat ID>/deleted/<message ID>/` | the photo, file or voice message |

The app can't read or change the archive (the security rules block it), and the
archived files have no download link. View them in the Firebase console under
*Firestore Database* and *Storage*.

## Testing

```sh
flutter test                 # unit tests
cd functions && npm test     # archive, notifications + security rules, on local emulators
```

`npm test` runs against the Firebase emulators, never the real project, and
needs Java 21 or newer (Android Studio's bundled `jbr` works: point `JAVA_HOME`
at it). To try the whole app against the emulators, run
`firebase emulators:start --only firestore,storage,functions` and build the app
with `--dart-define=USE_EMULATORS=true`.

## How privacy works without accounts

All data lives under one long random chat ID (`kChatId` in `lib/config.dart`).
The Firestore and Storage rules only allow that ID, and nobody can list which
chats exist, so the ID works like a shared password. **Don't share the APK**,
because the ID is inside it.

To use a new ID, change it in `lib/config.dart`, `firestore.rules` and
`storage.rules`, redeploy the rules, and rebuild the app.

## Project layout

```
lib/
  config.dart                 chat ID, limits, emulator switch
  main.dart                   Firebase init, first-launch routing
  models/message.dart         Message, ReplyRef, Member
  services/chat_service.dart  all Firestore / Storage reads and writes
  services/identity.dart      remembers who this phone is
  services/push.dart          push notification permission and tokens
  services/voice_recorder.dart, voice_player.dart   voice messages
  services/secure_screen.dart screenshot blocking for view once
  services/theme_settings.dart  the chosen theme, saved on this device
  theme.dart                  the color themes
  screens/                    setup, chat, chat theme, image preview / viewer, view once
  widgets/                    message bubbles, voice player, reply quotes,
                              links, swipe to reply, header with presence
functions/index.js            archive + push notifications
functions/notification.js     what a notification says
firestore.rules, storage.rules
web/firebase-messaging-sw.js  website notifications while it's closed
```

## Ideas for later

- App lock with a PIN or fingerprint
- Search messages
- Video messages with an inline player
- Link previews
- Pinned messages
- Paste or drag images into the website
