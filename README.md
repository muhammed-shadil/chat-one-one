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
- **One-time location sharing** (behind a feature flag): see
  [below](#one-time-location-sharing).

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
archived files have no download link. View them in the Firebase console under
*Firestore Database* and *Storage*.

## Testing

```sh
flutter test                 # unit and widget tests (location sharing uses mock coordinates)
cd functions && npm test     # archive, notifications, locations + security rules, on local emulators
```

`npm test` runs against the Firebase emulators, never the real project, and
needs Java 21 or newer (Android Studio's bundled `jbr` works: point `JAVA_HOME`
at it). To try the whole app against the emulators, run
`firebase emulators:start --only firestore,storage,functions` and build the app
with `--dart-define=USE_EMULATORS=true`.

## One-time location sharing

Switched on and off in `lib/core/config/feature_flags.dart`:

| Flag | What it does |
|---|---|
| `enableSurpriseLocation` | `false` removes the whole feature: no screen, no menu item, the location is never asked for or read. |
| `showOnEveryAppOpen` | `true` opens the invitation each time the app starts (for testing). `false` opens it once per person on each device; after that it's in the menu under **Shared location**. |

When the app starts, a full-screen invitation opens. Choosing **Share My
Location** asks for location permission (only then, and only "while using the
app"), reads the position **once**, and saves it. **Maybe Later** or ✕ closes
it with nothing asked. Menu → **Shared location** shows the other person's
location on a map (OpenStreetMap), with coordinates, when it was captured, its
accuracy, and **Open in Maps**. It also shows whether your own location is
shared, with **Stop sharing**, or a button to share yours once.

- **Stored** in `chats/<chat ID>/locations/<p1|p2>`, one document per person,
  so sharing again replaces it (no duplicates). Fields: `userId`, `latitude`,
  `longitude`, `accuracy` (meters), `capturedAt`, `sharedAt` (server time),
  `expiresAt`, `sharingType: "one_time"`.
- **Rules:** coordinates must be real, the document ID must match `userId`, the
  collection can't be listed, and nothing is archived when deleted. Like the
  messages, it's protected by the chat ID, not by accounts.
- **Retention:** `kLocationRetention` in `lib/config.dart` (7 days; the rules
  allow 30 at most). After that the rules refuse to return it and the app
  deletes it when the Shared location screen is opened. For deletion even if
  nobody opens it, turn on a Firestore TTL policy (one time):
  ```sh
  gcloud firestore fields ttls update expiresAt --collection-group=locations --enable-ttl --project=<your-project-id>
  ```
- **No tracking:** there is no position stream and no background location.
  Android asks only for `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`, and
  geolocator's background service is removed from the manifest. iOS has only
  `NSLocationWhenInUseUsageDescription`.

The new `locations` rules must be deployed (`firebase deploy --only
firestore:rules`) before sharing works against the real project.

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
  core/config/feature_flags.dart   switches for optional features
  main.dart                   Firebase init, first-launch routing
  models/message.dart         Message, ReplyRef, Member
  models/shared_location.dart a location shared one time
  services/chat_service.dart  all Firestore / Storage reads and writes
  services/identity.dart      remembers who this phone is
  services/push.dart          push notification permission and tokens
  services/voice_recorder.dart, voice_player.dart   voice messages
  services/theme_settings.dart  the chosen theme, saved on this device
  services/location_service.dart  reads the location once, with permission
  services/surprise_prompt.dart   when the location invitation opens by itself
  theme.dart                  the color themes
  screens/                    setup, chat, chat theme, image preview / viewer, view once,
                              location invitation, shared location
  widgets/surprise_effects.dart   gradient, glass, hearts, confetti
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
