import 'package:chat_one_one/admin_app.dart';
import 'package:chat_one_one/config.dart';
import 'package:chat_one_one/models/admin_photo.dart';
import 'package:chat_one_one/screens/admin_photos_screen.dart';
import 'package:chat_one_one/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _password = 'right password';

/// What the `adminPhotos` function returns, the way the web SDK hands it
/// over: untyped maps, and numbers that may be doubles.
Map<Object?, Object?> _data() {
  final t = DateTime(2026, 11, 21, 10, 30).millisecondsSinceEpoch.toDouble();
  Map<Object?, Object?> photo(String id, String status,
          {String? sender = 'p1', bool viewOnce = false, double? sentAt, Object? extra}) =>
      {
        'key': '$kChatId/$id',
        'chatId': kChatId,
        'messageId': id,
        'senderId': sender,
        'status': status,
        'viewOnce': viewOnce,
        'caption': null,
        'fileName': null,
        'sentAt': sentAt ?? t,
        'openedAt': null,
        'deletedAt': null,
        'width': 1920.0,
        'height': 1080,
        'size': 2048,
        'path': 'chats/$kChatId/images/$id.jpg',
        'url': null,
        ...?extra as Map<Object?, Object?>?,
      };
  return {
    'chats': [
      {
        'id': kChatId,
        'names': {'p1': 'Asha', 'p2': 'Ravi'},
        'photoCount': 5,
      },
    ],
    'photos': [
      photo('beach', 'chat', extra: {'caption': 'Beach day'}),
      photo('secret', 'view_once', sender: 'p2', viewOnce: true),
      photo('seen', 'opened', viewOnce: true, extra: {'openedAt': t + 60000}),
      photo('gone', 'deleted', sender: 'p2', extra: {'deletedAt': t + 120000}),
      photo('orphan', 'unlinked', sender: null, sentAt: t - 86400000 * 400),
    ],
    'linksExpireAt': t + 7200000,
  };
}

void main() {
  test('the admin page is at /admin/photos (or just /admin)', () {
    expect(kAdminPhotosPath, '/admin/photos');
    expect(isAdminPath('/admin/photos'), isTrue);
    expect(isAdminPath('/admin'), isTrue);
    expect(isAdminPath('/'), isFalse);
    expect(isAdminPath('/administrator'), isFalse);
  });

  test('the function result is read whatever map and number types it uses', () {
    final list = AdminPhotoList.fromData(_data());
    expect(list.chats.single.isCurrent, isTrue);
    expect(list.photos.map((p) => p.status), [
      PhotoStatus.chat,
      PhotoStatus.viewOnce,
      PhotoStatus.opened,
      PhotoStatus.deleted,
      PhotoStatus.unlinked,
    ]);
    final beach = list.photos.first;
    expect(beach.caption, 'Beach day');
    expect(beach.width, 1920);
    expect(beach.sentAt, DateTime(2026, 11, 21, 10, 30));
    expect(list.photos[2].openedAt, DateTime(2026, 11, 21, 10, 31));
    expect(list.nameOf(kChatId, 'p2'), 'Ravi');
    expect(list.nameOf('old', 'p1'), 'Person 1');
    expect(list.nameOf(kChatId, null), 'Unknown');
  });

  group('admin photos page', () {
    late List<String> tried;

    Future<AdminPhotoList> load(String password) async {
      tried.add(password);
      if (password != _password) {
        throw const AdminException('Wrong password.', wrongPassword: true);
      }
      return AdminPhotoList.fromData(_data());
    }

    Future<void> open(WidgetTester tester) async {
      tried = [];
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: AdminPhotosScreen(loadPhotos: load)));
    }

    Future<void> unlock(WidgetTester tester, String password) async {
      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows nothing until the password is right', (tester) async {
      await open(tester);
      expect(find.text('Admin password'), findsOneWidget);

      await unlock(tester, 'guess');
      expect(find.text('Wrong password.'), findsOneWidget);
      expect(find.text('Photos'), findsNothing);

      await unlock(tester, _password);
      expect(tried, ['guess', _password]);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('5 photos'), findsOneWidget);
    });

    testWidgets('lists every kind of photo, and filters by kind and person', (tester) async {
      await open(tester);
      await unlock(tester, _password);

      expect(find.text('All  5'), findsOneWidget);
      expect(find.text('In chat  1'), findsOneWidget);
      expect(find.text('View once, not opened  1'), findsOneWidget);
      expect(find.text('View once, opened  1'), findsOneWidget);
      expect(find.text('Deleted  1'), findsOneWidget);
      expect(find.text('Storage only  1'), findsOneWidget);
      expect(find.text('Not opened'), findsOneWidget);
      expect(find.text('Opened'), findsOneWidget);
      expect(find.text('Deleted'), findsOneWidget);

      await tester.tap(find.text('Deleted  1'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 5'), findsOneWidget);
      expect(find.textContaining('Ravi ·'), findsOneWidget);
      expect(find.textContaining('Asha ·'), findsNothing);

      await tester.tap(find.text('All  5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asha  2'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 5'), findsOneWidget);
      // Counts follow the person filter.
      expect(find.text('Deleted  0'), findsOneWidget);
    });

    testWidgets('a photo opens full screen with its details', (tester) async {
      await open(tester);
      await unlock(tester, _password);

      await tester.tap(find.text('View once, opened  1'));
      await tester.pumpAndSettle();
      // The tile's tap area lies over its label.
      await tester.tap(find.textContaining('Asha ·'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('1 of 1'), findsOneWidget);
      expect(find.textContaining('Opened '), findsWidgets);
      expect(find.textContaining('1920 × 1080'), findsOneWidget);
      expect(find.textContaining('chats/$kChatId/images/seen.jpg'), findsOneWidget);
    });

    testWidgets('Lock hides the photos and asks for the password again', (tester) async {
      await open(tester);
      await unlock(tester, _password);

      await tester.tap(find.byTooltip('Lock'));
      await tester.pumpAndSettle();
      expect(find.text('Admin password'), findsOneWidget);
      expect(find.text('Photos'), findsNothing);
    });
  });
}
