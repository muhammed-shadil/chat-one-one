/// The single private conversation this app talks to.
///
/// This ID works like a password: it is also written into `firestore.rules`
/// and `storage.rules`, and only data under this ID can be read or written.
/// If you change it, change it in all three places and redeploy the rules.
const String kChatId = 'rhxd7yqwcq6xant5r6k5nzvx';

/// Build with `--dart-define=USE_EMULATORS=true` to talk to the local Firebase
/// emulators (`firebase emulators:start`) instead of the real project. Push
/// notifications are off in that mode, since the emulators can't send them.
const bool kUseEmulators = bool.fromEnvironment('USE_EMULATORS');

/// Where the Cloud Functions run, as in `functions/index.js`.
const String kFunctionsRegion = 'asia-south1';

/// The website's private admin page, which shows every photo, including
/// opened view-once and deleted ones. Password-protected by Cloud Functions.
const String kAdminPhotosPath = '/admin/photos';

/// The two people in the chat. Their display names are chosen inside the app
/// on first launch, so nothing here needs editing.
const String kPerson1 = 'p1';
const String kPerson2 = 'p2';

String otherPerson(String me) => me == kPerson1 ? kPerson2 : kPerson1;

/// Largest file that can be sent. Keep in sync with `storage.rules`.
const int kMaxUploadBytes = 100 * 1024 * 1024;

/// How many messages to load at first, and how many more each time the user
/// scrolls to the top.
const int kPageSize = 40;
