/// This project runs two completely separate chats, each between two people,
/// with its own website and its own admin page:
///
/// | Build with              | Chat   | Website                                |
/// |-------------------------|--------|----------------------------------------|
/// | (nothing)               | first  | https://chat-one-one-66cbf.web.app     |
/// | `--dart-define=CHAT=2`  | second | https://chat-one-one-2-xevg3.web.app   |
///
/// A build only contains its own chat's ID, so neither chat can reach the
/// other's messages, photos or admin page.
const String kChat = String.fromEnvironment('CHAT', defaultValue: '1');

/// The chats [kChat] can name. Any other value stops the app at startup, so a
/// typo can never put one chat on the other's website.
const List<String> kKnownChats = ['1', '2'];

const bool _isSecondChat = kChat == '2';

/// The private conversation this build talks to.
///
/// Each ID works like a password: both are also written into
/// `firestore.rules`, `storage.rules` and `functions/chats.js`, and only data
/// under these IDs can be read or written. If you change one, change it in
/// all four places, redeploy the rules and functions, and rebuild the app.
const String kChatId = _isSecondChat ? kSecondChatId : kFirstChatId;

const String kFirstChatId = 'rhxd7yqwcq6xant5r6k5nzvx';
const String kSecondChatId = '4drjzcca8t69rrduir7z2hnk';

/// The Cloud Function behind this chat's admin page (`functions/index.js`).
/// Each chat has its own, locked by its own password, listing only its photos.
const String kAdminPhotosFunction = _isSecondChat ? 'adminPhotos2' : 'adminPhotos';

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
