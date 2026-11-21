import 'dart:async';

import 'package:chat_one_one/config.dart';
import 'package:chat_one_one/models/shared_location.dart';
import 'package:chat_one_one/screens/shared_location_screen.dart';
import 'package:chat_one_one/screens/surprise_screen.dart';
import 'package:chat_one_one/services/chat_service.dart';
import 'package:chat_one_one/services/location_service.dart';
import 'package:chat_one_one/services/surprise_prompt.dart';
import 'package:chat_one_one/theme.dart';
import 'package:chat_one_one/utils/format.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mock coordinates (Bengaluru), as from a phone with a good GPS fix.
final mockFix = LocationFix(
  latitude: 12.971599,
  longitude: 77.594566,
  accuracy: 14,
  capturedAt: DateTime.utc(2026, 11, 21, 10, 30),
);

/// Stands in for the device: permission answers and a mock position.
class FakeLocationSource implements LocationSource {
  FakeLocationSource({
    this.serviceEnabled = true,
    this.permission = LocationPermission.denied,
    this.answer = LocationPermission.whileInUse,
    LocationFix? fix,
    this.error,
  }) : fix = fix ?? mockFix;

  bool serviceEnabled;

  /// The current permission, and what the person picks when asked.
  LocationPermission permission;
  LocationPermission answer;
  LocationFix fix;
  Object? error;

  int asked = 0, read = 0, appSettings = 0, locationSettings = 0;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    asked++;
    return permission = answer;
  }

  @override
  Future<LocationFix> currentPosition(Duration timeLimit) async {
    read++;
    if (error != null) throw error!;
    return fix;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettings++;
    return true;
  }
}

/// Records what would be written to Firestore, without Firebase.
class FakeChat extends ChatService {
  FakeChat({String me = kPerson1}) : super(me, onError: (_) {});

  final shared = <LocationFix>[];
  final deleted = <String>[];
  final current = <String, SharedLocation?>{};

  /// Thrown by [shareLocation] once, if set.
  Object? shareError;

  /// While set, [shareLocation] waits for it (still "sending").
  Completer<void>? hold;

  @override
  Future<void> shareLocation(
    LocationFix fix, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await hold?.future;
    final error = shareError;
    shareError = null;
    if (error != null) throw error;
    shared.add(fix);
  }

  @override
  Stream<SharedLocation?> watchSharedLocation(String personId) =>
      Stream.value(current[personId]);

  @override
  void deleteSharedLocation(String personId) => deleted.add(personId);
}

SharedLocation sharedBy(String personId, {LocationFix? fix}) => SharedLocation(
      userId: personId,
      fix: fix ?? mockFix,
      sharedAt: DateTime.utc(2026, 11, 21, 10, 31),
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );

/// A phone-sized screen, with the looping animations off so the tests can
/// wait for everything to settle.
Future<void> pumpApp(WidgetTester tester, Widget home,
    {bool animations = false}) async {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light, kPalettes.first),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: !animations),
      child: child!,
    ),
    home: home,
  ));
}

/// The chat underneath, with a button that opens the surprise like the app.
Future<void> openSurprise(WidgetTester tester, FakeChat chat,
    FakeLocationSource source, {bool animations = false}) async {
  await pumpApp(
    tester,
    animations: animations,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(SurpriseScreen.route(
              chat: chat,
              partnerName: 'Sam',
              location: LocationService(source),
            )),
            child: const Text('the chat'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('the chat'));
  if (animations) {
    await tester.pump(const Duration(milliseconds: 600));
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  group('formatting', () {
    test('coordinates, accuracy and retention', () {
      expect(formatCoordinates(12.9715987, -77.5945627), '12.971599, -77.594563');
      expect(formatAccuracy(14.4), '± 14 m');
      expect(formatAccuracy(1500), '± 1.5 km');
      expect(formatAccuracy(25000), '± 25 km');
      expect(formatRetention(const Duration(days: 7)), '7 days');
      expect(formatRetention(const Duration(days: 1)), '1 day');
      expect(formatRetention(const Duration(hours: 12)), '12 hours');
    });

    test('a moment reads as day and time', () {
      final now = DateTime(2026, 11, 21, 18);
      final morning = DateTime(2026, 11, 21, 9, 5);
      final lastNight = DateTime(2026, 11, 20, 21, 30);
      // (intl puts a narrow no-break space before AM / PM, so compare with it.)
      expect(formatMoment(morning, now: now), 'Today at ${formatTime(morning)}');
      expect(formatMoment(lastNight, now: now),
          'Yesterday at ${formatTime(lastNight)}');
      expect(formatTime(morning), startsWith('9:05'));
    });
  });

  group('a shared location', () {
    test('only real coordinates and a usable accuracy are valid', () {
      LocationFix at(double lat, double lng, [double acc = 10]) => LocationFix(
          latitude: lat, longitude: lng, accuracy: acc, capturedAt: DateTime(2026));
      expect(at(90, 180).isValid, isTrue);
      expect(at(-90, -180).isValid, isTrue);
      expect(at(90.01, 0).isValid, isFalse);
      expect(at(0, -180.01).isValid, isFalse);
      expect(at(double.nan, 0).isValid, isFalse);
      expect(at(0, double.infinity).isValid, isFalse);
      expect(at(0, 0, -1).isValid, isFalse);
      expect(at(0, 0, 100001).isValid, isFalse);
    });

    test('is saved with the fields the security rules expect', () {
      final map = sharedBy(kPerson2).toFirestore();
      expect(map.keys.toSet(), {
        'userId', 'latitude', 'longitude', 'accuracy',
        'capturedAt', 'sharedAt', 'expiresAt', 'sharingType',
      });
      expect(map['userId'], kPerson2);
      expect(map['sharingType'], 'one_time');
      expect(map['sharedAt'], isA<FieldValue>(), reason: 'set by the server');
      expect(map['capturedAt'], Timestamp.fromDate(mockFix.capturedAt));
    });

    test('is read back, and anything malformed is ignored', () {
      final doc = {
        'latitude': 12.5,
        'longitude': 77,
        'accuracy': 8,
        'capturedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 21)),
        'sharedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 21, 0, 1)),
        'expiresAt': Timestamp.fromDate(DateTime.utc(2026, 11, 28)),
      };
      final location = SharedLocation.fromMap(kPerson2, doc)!;
      expect(location.userId, kPerson2);
      expect(location.fix.longitude, 77.0);
      expect(location.isExpired(DateTime.utc(2026, 11, 27)), isFalse);
      expect(location.isExpired(DateTime.utc(2026, 11, 28)), isTrue);

      expect(SharedLocation.fromMap(kPerson2, null), isNull);
      expect(SharedLocation.fromMap(kPerson2, {...doc, 'latitude': '12.5'}), isNull);
      expect(SharedLocation.fromMap(kPerson2, {...doc, 'latitude': 95}), isNull);
      expect(SharedLocation.fromMap(kPerson2, {...doc}..remove('expiresAt')), isNull);
    });
  });

  group('when the surprise opens by itself', () {
    test('the flags decide', () {
      bool show(bool enabled, bool everyOpen, bool shown) => SurprisePrompt.shouldShow(
          enabled: enabled, everyOpen: everyOpen, alreadyShown: shown);
      expect(show(false, true, false), isFalse, reason: 'feature off');
      expect(show(false, false, false), isFalse, reason: 'feature off');
      expect(show(true, true, true), isTrue, reason: 'every open');
      expect(show(true, false, false), isTrue, reason: 'first time');
      expect(show(true, false, true), isFalse, reason: 'already shown');
    });

    test('off: never, and nothing is remembered', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await SurprisePrompt.takeTurn(kPerson1, enabled: false), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('every open: each time, without being marked done', () async {
      SharedPreferences.setMockInitialValues({});
      for (var i = 0; i < 3; i++) {
        expect(await SurprisePrompt.takeTurn(kPerson1, enabled: true, everyOpen: true),
            isTrue);
      }
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });

    test('once: the first time for each person on this device', () async {
      SharedPreferences.setMockInitialValues({});
      Future<bool> turn(String who) =>
          SurprisePrompt.takeTurn(who, enabled: true, everyOpen: false);
      expect(await turn(kPerson1), isTrue);
      expect(await turn(kPerson1), isFalse);
      expect(await turn(kPerson2), isTrue, reason: 'after switching person');
      expect(await turn(kPerson2), isFalse);
    });
  });

  group('taking the location once', () {
    test('already allowed: no question, just the position', () async {
      final source = FakeLocationSource(permission: LocationPermission.whileInUse);
      final result = await LocationService(source).captureOnce();
      expect(result.fix, same(mockFix));
      expect(source.asked, 0);
      expect(source.read, 1);
    });

    test('not asked yet: asks once, then reads it', () async {
      final source = FakeLocationSource();
      final result = await LocationService(source).captureOnce();
      expect(result.fix, same(mockFix));
      expect(source.asked, 1);
      expect(source.read, 1);
    });

    test('refused: no position is read', () async {
      final source = FakeLocationSource(answer: LocationPermission.denied);
      final result = await LocationService(source).captureOnce();
      expect(result.problem, LocationProblem.denied);
      expect(source.asked, 1);
      expect(source.read, 0);
    });

    test('refused for good: not asked again, settings offered', () async {
      final source = FakeLocationSource(permission: LocationPermission.deniedForever);
      final service = LocationService(source);
      final result = await service.captureOnce();
      expect(result.problem, LocationProblem.deniedForever);
      expect(source.asked, 0);
      expect(source.read, 0);
      expect(result.problem!.canOpenSettings, isTrue);
      await service.openSettingsFor(result.problem!);
      expect(source.appSettings, 1);
    });

    test('location switched off: nothing asked, location settings offered', () async {
      final source = FakeLocationSource(serviceEnabled: false);
      final service = LocationService(source);
      final result = await service.captureOnce();
      expect(result.problem, LocationProblem.serviceDisabled);
      expect(source.asked, 0);
      expect(source.read, 0);
      await service.openSettingsFor(result.problem!);
      expect(source.locationSettings, 1);
    });

    test('no fix in time, or a nonsense one', () async {
      final slow = FakeLocationSource(
          permission: LocationPermission.whileInUse, error: TimeoutException('gps'));
      expect((await LocationService(slow).captureOnce()).problem, LocationProblem.timeout);

      final broken = FakeLocationSource(
          permission: LocationPermission.whileInUse,
          fix: LocationFix(
              latitude: 200, longitude: 0, accuracy: 5, capturedAt: DateTime(2026)));
      expect((await LocationService(broken).captureOnce()).problem,
          LocationProblem.unavailable);
    });
  });

  group('the surprise screen', () {
    testWidgets('invites first, and asks nothing until Share is tapped',
        (tester) async {
      final chat = FakeChat(), source = FakeLocationSource();
      await openSurprise(tester, chat, source);

      expect(find.text('A Little Surprise Awaits ❤️'), findsOneWidget);
      expect(find.text("Let's make a little memory together. There's something "
          'special waiting for you!'), findsOneWidget);
      await tapText(tester, 'Discover Now ❤️');

      expect(find.text('Share Your Current Location'), findsOneWidget);
      expect(find.text('Share your current location once so we can stay connected.'),
          findsOneWidget);
      expect(find.text('Only Sam can see it'), findsOneWidget);
      expect(find.text('Deleted automatically after 7 days'), findsOneWidget);
      expect(source.asked + source.read, 0, reason: 'only after Share My Location');
      expect(chat.shared, isEmpty);
    });

    testWidgets('Maybe Later goes back to the chat without asking anything',
        (tester) async {
      final chat = FakeChat(), source = FakeLocationSource();
      await openSurprise(tester, chat, source);
      await tapText(tester, 'Discover Now ❤️');
      await tapText(tester, 'Maybe Later');

      expect(find.text('the chat'), findsOneWidget);
      expect(find.byType(SurpriseScreen), findsNothing);
      expect(source.asked + source.read, 0);
      expect(chat.shared, isEmpty);
    });

    testWidgets('the invitation can be closed', (tester) async {
      final chat = FakeChat(), source = FakeLocationSource();
      await openSurprise(tester, chat, source);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(SurpriseScreen), findsNothing);
    });

    testWidgets('allowed: shares the mock location once, then celebrates',
        (tester) async {
      final chat = FakeChat(), source = FakeLocationSource();
      await openSurprise(tester, chat, source);
      await tapText(tester, 'Discover Now ❤️');
      await tapText(tester, 'Share My Location');

      expect(source.asked, 1);
      expect(chat.shared, [same(mockFix)]);
      expect(find.text('Successfully Connected! ❤️'), findsOneWidget);
      expect(find.text('Your location has been shared successfully.'), findsOneWidget);

      await tapText(tester, 'Continue Chatting');
      expect(find.text('the chat'), findsOneWidget);
      expect(find.byType(SurpriseScreen), findsNothing);
    });

    testWidgets('refused: says so, shares nothing, and can be tried again',
        (tester) async {
      final chat = FakeChat(),
          source = FakeLocationSource(answer: LocationPermission.denied);
      await openSurprise(tester, chat, source);
      await tapText(tester, 'Discover Now ❤️');
      await tapText(tester, 'Share My Location');

      expect(find.text(LocationProblem.denied.message), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
      expect(chat.shared, isEmpty);

      source.answer = LocationPermission.whileInUse;
      await tapText(tester, 'Share My Location');
      expect(source.asked, 2, reason: 'asked again only because it was tapped');
      expect(chat.shared, hasLength(1));
      expect(find.text('Successfully Connected! ❤️'), findsOneWidget);
    });

    testWidgets('refused for good: offers Settings instead of asking',
        (tester) async {
      final chat = FakeChat(),
          source = FakeLocationSource(permission: LocationPermission.deniedForever);
      await openSurprise(tester, chat, source);
      await tapText(tester, 'Discover Now ❤️');
      await tapText(tester, 'Share My Location');

      expect(find.text(LocationProblem.deniedForever.message), findsOneWidget);
      await tapText(tester, 'Open Settings');
      expect(source.appSettings, 1);
      expect(source.asked, 0);
      expect(chat.shared, isEmpty);
    });

    testWidgets('location switched off: offers to turn it on', (tester) async {
      final chat = FakeChat(), source = FakeLocationSource(serviceEnabled: false);
      await openSurprise(tester, chat, source);
      await tapText(tester, 'Discover Now ❤️');
      await tapText(tester, 'Share My Location');

      expect(find.text(LocationProblem.serviceDisabled.message), findsOneWidget);
      await tapText(tester, 'Turn on location');
      expect(source.locationSettings, 1);
      expect(chat.shared, isEmpty);
    });

    testWidgets('a failed upload says so and can be retried', (tester) async {
      final chat = FakeChat()
            ..shareError = FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          source = FakeLocationSource();
      await openSurprise(tester, chat, source);
      await tapText(tester, 'Discover Now ❤️');
      await tapText(tester, 'Share My Location');

      expect(find.textContaining("Couldn't share your location"), findsOneWidget);
      expect(find.text('Successfully Connected! ❤️'), findsNothing);

      await tapText(tester, 'Share My Location');
      expect(chat.shared, hasLength(1));
      expect(find.text('Successfully Connected! ❤️'), findsOneWidget);
    });

    testWidgets('offline: says it will be sent once back online', (tester) async {
      final chat = FakeChat()..shareError = TimeoutException('offline'),
          source = FakeLocationSource();
      await openSurprise(tester, chat, source);
      await tapText(tester, 'Discover Now ❤️');
      await tapText(tester, 'Share My Location');

      expect(find.text('Successfully Connected! ❤️'), findsOneWidget);
      expect(find.textContaining("as soon as you're back online"), findsOneWidget);
    });

    testWidgets('tapping again while sending does not share twice',
        (tester) async {
      final chat = FakeChat()..hold = Completer<void>(),
          source = FakeLocationSource();
      await openSurprise(tester, chat, source);
      await tapText(tester, 'Discover Now ❤️');
      await tester.ensureVisible(find.text('Share My Location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share My Location'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Sharing…'), findsOneWidget);
      await tester.tap(find.text('Sharing…'));
      await tester.tap(find.text('Maybe Later'), warnIfMissed: false);
      await tester.pump();
      expect(source.read, 1);
      expect(find.byType(SurpriseScreen), findsOneWidget, reason: "can't leave mid-way");

      chat.hold!.complete();
      await tester.pumpAndSettle();
      expect(chat.shared, hasLength(1));
      expect(find.text('Successfully Connected! ❤️'), findsOneWidget);
    });

    testWidgets('the animations run without errors', (tester) async {
      final chat = FakeChat(), source = FakeLocationSource();
      await openSurprise(tester, chat, source, animations: true);
      Future<void> frames(int n) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await frames(20);
      await tester.ensureVisible(find.text('Discover Now ❤️'));
      await tester.tap(find.text('Discover Now ❤️'));
      await frames(20);
      await tester.ensureVisible(find.text('Share My Location'));
      await tester.tap(find.text('Share My Location'));
      // Confetti, hearts and ripples, through to the confetti's end.
      await frames(90);
      expect(find.text('Successfully Connected! ❤️'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Stop the endless loops before the test ends.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the shared location viewer', () {
    testWidgets("shows the other person's location with its details",
        (tester) async {
      final chat = FakeChat()..current[kPerson2] = sharedBy(kPerson2);
      await pumpApp(tester, SharedLocationScreen(chat: chat, partnerName: 'Sam'));
      await tester.pump();

      expect(find.byType(LocationMap), findsOneWidget);
      expect(find.text('12.971599, 77.594566'), findsOneWidget);
      expect(find.text('± 14 m'), findsOneWidget);
      expect(find.text(formatMoment(mockFix.capturedAt)), findsOneWidget);
      expect(find.text('Open in Maps'), findsOneWidget);
      expect(find.text("Sam can't see your location."), findsOneWidget);

      await tester.ensureVisible(find.text('Delete'));
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      expect(chat.deleted, [kPerson2]);
    });

    testWidgets('nothing shared yet; my own is shared only when I choose',
        (tester) async {
      final chat = FakeChat(), source = FakeLocationSource();
      await pumpApp(tester,
          SharedLocationScreen(chat: chat, partnerName: 'Sam', location: LocationService(source)));
      await tester.pumpAndSettle();

      expect(find.text("Sam hasn't shared a location"), findsOneWidget);
      expect(find.byType(LocationMap), findsNothing);
      expect(source.asked + source.read, 0);

      await tapText(tester, 'Share my location once');
      expect(find.text('Share your location?'), findsOneWidget);
      expect(source.asked + source.read, 0, reason: 'not before confirming');

      await tapText(tester, 'Share');
      expect(chat.shared, [same(mockFix)]);
      expect(find.text('Your location is shared with Sam.'), findsOneWidget);
    });

    testWidgets('my shared location can be stopped', (tester) async {
      final chat = FakeChat()..current[kPerson1] = sharedBy(kPerson1);
      await pumpApp(tester, SharedLocationScreen(chat: chat, partnerName: 'Sam'));
      await tester.pumpAndSettle();

      expect(find.textContaining('You shared your location'), findsOneWidget);
      await tapText(tester, 'Stop sharing');
      await tester.tap(find.widgetWithText(FilledButton, 'Stop sharing'));
      await tester.pump();
      expect(chat.deleted, [kPerson1]);
    });

    test('Open in Maps uses Apple Maps on iPhone, Google Maps elsewhere', () {
      final google = mapsUri(mockFix, platform: TargetPlatform.android);
      expect(google.host, 'www.google.com');
      expect(google.queryParameters['query'], '12.971599,77.594566');
      final apple = mapsUri(mockFix, platform: TargetPlatform.iOS);
      expect(apple.host, 'maps.apple.com');
      expect(apple.queryParameters['ll'], '12.971599,77.594566');
    });
  });

  test("the retention fits within the security rules' 30-day limit", () {
    expect(kLocationRetention > Duration.zero, isTrue);
    expect(kLocationRetention <= const Duration(days: 30), isTrue);
  });
}
