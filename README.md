# Chat One One

A private chat app for exactly two people. There's no login or sign-up: on first
launch, each phone picks **Person 1** or **Person 2** and enters a name, and that's it.

## Features

- Text messages, with sent ✓ and seen ✓✓ (blue) ticks
- Photos from the camera or gallery, with an optional caption
- **View once** photos: the receiver can open them a single time. The photo is
  deleted from Firebase Storage as soon as it's opened, and screenshots are
  blocked on Android while it's on screen.
- Files of any type (PDF, DOC, ZIP, APK, …) up to 100 MB. Tap a file to download and open it.
- Online status, "typing…" and "last seen"
- Date separators, and older messages load as you scroll up
- Long-press a message to copy it, or to delete your own message for everyone
- Light and dark themes, and messages still show offline (Firestore cache)

## What's required

| Item | Why |
|---|---|
| Flutter SDK (3.41+) | to build the app |
| A Firebase project | backend |
| **Cloud Firestore** | stores messages, names, and online status |
| **Cloud Storage for Firebase** | stores photos and files |
| **Blaze (pay-as-you-go) plan** | Google requires it to enable Cloud Storage. Two people chatting stay inside the free quota (5 GB stored, 1 GB downloaded per day, 50k Firestore reads per day), so the expected cost is ₹0. Set a budget alert to be safe. |
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
5. **Deploy the security rules:**
   ```sh
   firebase deploy --only firestore:rules,storage --project <your-project-id>
   ```
6. **Build and install** on both phones:
   ```sh
   flutter build apk --release
   # output: build/app/outputs/flutter-apk/app-release.apk
   ```
7. Open the app on each phone. One person picks **Person 1** and the other picks **Person 2**.

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
  config.dart                 chat ID, limits
  main.dart                   Firebase init, first-launch routing
  models/message.dart         Message + Member
  services/chat_service.dart  all Firestore / Storage reads and writes
  services/identity.dart      remembers who this phone is
  services/secure_screen.dart screenshot blocking for view once
  screens/                    setup, chat, image preview / viewer, view once
  widgets/                    message bubbles, header with online status
firestore.rules, storage.rules
```

## Not included yet

- **Push notifications when the app is closed.** These need Firebase Cloud
  Messaging plus a Cloud Function that sends a push on each new message.
- Voice notes, replies and reactions.
