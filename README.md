# Chat One One

A private chat app for exactly two people. There's no login or sign-up: on first
launch, each phone picks **Person 1** or **Person 2** and enters a name, and that's it.

## Features

- Text messages, with sent ✓ and seen ✓✓ (blue) ticks
- Photos from the camera or gallery, with an optional caption
- **View once** photos: the receiver can open them a single time. As soon as
  it's opened the photo leaves the chat and moves to the private
  [archive](#archive-of-opened-deleted-and-edited-messages).
- **No screenshots or screen recording** anywhere in the Android app (see
  [Screenshot protection](#screenshot-protection)).
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
| **Cloud Functions** | keeps the archive, sends push notifications, and runs the [admin page](#admin-page-every-photo) |
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

In the browser, files open in a new tab instead of being saved in the app.

## Screenshot protection

| Where | What's protected |
|---|---|
| **Android app** | Every screen: screenshots and screen recordings come out black, and the app is blank in the recent-apps switcher and when casting (`FLAG_SECURE`, set in `MainActivity.kt`). |
| **Website** | Browsers can't block screenshots or recording. As a deterrent, full-screen photos and view once photos are covered whenever the window loses focus or the tab is hidden (`lib/widgets/private_view.dart`); photos can't be saved or dragged out with the mouse; and printing / "Save as PDF" shows a blank page (`web/index.html`). |
| **iPhone app** | iOS has no supported way to block screenshots, so nothing extra. |

No app can stop someone photographing the screen with another phone.

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
archived files have no download link. View them on the
[admin page](#admin-page-every-photo), or in the Firebase console under
*Firestore Database* and *Storage*.

## Admin page: every photo

The website has a private page at
<https://chat-one-one-66cbf.web.app/admin/photos> that shows every photo the
chat has ever held, newest first and grouped by day, straight away:

| Label | What it is |
|---|---|
| In chat | photos still in the chat, including images sent as a file |
| View once, not opened | view once photos the other person hasn't opened yet |
| View once, opened | opened view once photos, from the archive |
| Deleted | photos deleted for everyone, from the archive |
| Storage only | image files in Storage that no message points to, e.g. a send that was interrupted (only shown if there are any) |

Filter by kind and by person. Click a photo to see it full screen with when it
was sent, opened or deleted, its caption, size and Storage path; swipe or use
the arrow keys to go through them, and Esc to close.

Opening this page never opens the chat: nobody shows as online, nothing is
marked seen, and view once photos stay unopened.

**How it's protected.** The page asks for an admin password and sends it to
the `adminPhotos` Cloud Function, which compares it with the `ADMIN_PASSWORD`
secret and only then lists the photos. The security rules are unchanged, so
the page itself still can't read the archive. Each photo loads through a link
signed by the `adminPhoto` function that stops working after one to two hours
(the page fetches new ones by itself), and archived files still have no
download link of their own. The password is kept only in the open tab:
reloading the page asks again, and **Lock** forgets it.

**Setting it up** (once):

```sh
# Pick a long password (at least 12 characters). This also turns on Secret
# Manager, which is free at this size.
firebase functions:secrets:set ADMIN_PASSWORD --project chat-one-one-66cbf
firebase deploy --only functions --project chat-one-one-66cbf
# The first build after cloud_functions was added needs a fresh plugin list,
# or the page fails with "Int64 accessor not supported by dart2js".
rm -rf .dart_tool/flutter_build
flutter build web --release
firebase deploy --only hosting --project chat-one-one-66cbf
```

To change the password, run the `secrets:set` command again and redeploy the
functions. Links handed out before stop working.

With the emulators, the password is the `ADMIN_PASSWORD=` line in
`functions/.secret.local` (kept out of git; `npm test` creates it with a
random password if it's missing). Without it, the emulators would ask the real
project's Secret Manager. Open `http://localhost:<port>/admin/photos` on a
web build made with `--dart-define=USE_EMULATORS=true`.

## Testing

```sh
flutter test                 # unit tests
cd functions && npm test     # archive, notifications, admin page + security rules, on local emulators
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
  services/theme_settings.dart  the chosen theme, saved on this device
  admin_app.dart, screens/admin_*, services/admin_service.dart,
  models/admin_photo.dart     the website's /admin/photos page
  theme.dart                  the color themes
  screens/                    setup, chat, chat theme, image preview / viewer, view once
  widgets/                    message bubbles, voice player, reply quotes,
                              links, swipe to reply, header with presence
functions/index.js            archive + push notifications + admin page
functions/admin.js            what the admin page lists, and its signed links
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
