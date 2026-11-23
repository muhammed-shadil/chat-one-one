import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/admin_photo.dart';
import '../services/admin_service.dart';
import '../utils/format.dart';
import '../widgets/admin_photo_image.dart';
import 'admin_photo_viewer_screen.dart';

/// The website's admin page (/admin/photos): after the admin password, a
/// grid of every photo the chat holds, archived ones included, by day.
class AdminPhotosScreen extends StatefulWidget {
  const AdminPhotosScreen({super.key, required this.loadPhotos});

  final PhotoLoader loadPhotos;

  @override
  State<AdminPhotosScreen> createState() => _AdminPhotosScreenState();
}

class _AdminPhotosScreenState extends State<AdminPhotosScreen> {
  final _passwordField = TextEditingController();
  bool _obscure = true;

  /// Kept in memory only: reloading the page asks for it again.
  String? _password;
  AdminPhotoList? _list;
  bool _loading = false;
  String? _lockError;
  Timer? _refresh;

  // Filters; null shows everything.
  PhotoStatus? _status;

  /// p1, p2, or '' for files without a sender.
  String? _sender;
  String? _chatId;

  @override
  void dispose() {
    _refresh?.cancel();
    _passwordField.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _passwordField.text;
    if (password.isEmpty || _loading) return;
    await _load(password);
  }

  Future<void> _load(String password) async {
    setState(() => _loading = true);
    try {
      final list = await widget.loadPhotos(password);
      if (!mounted) return;
      setState(() {
        _password = password;
        _list = list;
        _loading = false;
        _lockError = null;
      });
      _scheduleRefresh(list.linksExpireAt);
      // Lets the browser offer to remember the password.
      TextInput.finishAutofillContext();
    } on AdminException catch (e) {
      _failed(e.message, lock: e.wrongPassword);
    } catch (e, stack) {
      // In the browser console, to see what went wrong.
      debugPrint('Admin photos failed: $e\n$stack');
      _failed('Could not load the photos: $e');
    }
  }

  void _failed(String message, {bool lock = false}) {
    if (!mounted) return;
    final onLockScreen = _list == null || lock;
    setState(() {
      _loading = false;
      if (onLockScreen) {
        _clear();
        _lockError = message;
      }
    });
    if (!onLockScreen) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Photo links stop working after an hour or two; fetch fresh ones before.
  void _scheduleRefresh(DateTime linksExpireAt) {
    _refresh?.cancel();
    var wait = linksExpireAt.difference(DateTime.now()) -
        const Duration(minutes: 10);
    if (wait < const Duration(minutes: 1)) wait = const Duration(minutes: 1);
    _refresh = Timer(wait, () {
      final password = _password;
      if (password != null && mounted) _load(password);
    });
  }

  void _lock() => setState(() {
        _clear();
        _passwordField.clear();
        _lockError = null;
      });

  void _clear() {
    _refresh?.cancel();
    _password = null;
    _list = null;
    // Drop the decoded photos from memory too.
    PaintingBinding.instance.imageCache.clear();
  }

  bool _matches(AdminPhoto p,
          {bool status = true, bool sender = true, bool chat = true}) =>
      (!status || _status == null || p.status == _status) &&
      (!sender || _sender == null || (p.senderId ?? '') == _sender) &&
      (!chat || _chatId == null || p.chatId == _chatId);

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) return _buildLock(context);

    final shown = list.photos.where(_matches).toList();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Photos', style: TextStyle(fontSize: 18)),
            Text(
              shown.length == list.photos.length
                  ? _count(list.photos.length, 'photo')
                  : '${shown.length} of ${list.photos.length}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () => _load(_password!),
            ),
          IconButton(
            tooltip: 'Lock',
            icon: const Icon(Icons.lock_outline),
            onPressed: _lock,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildFilters(list)),
          if (shown.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    list.photos.isEmpty ? 'No photos yet.' : 'No photos match these filters.',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ..._buildDays(list, shown),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }

  Widget _buildLock(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 40, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text('Admin · Photos', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(
                        'Every photo in the chat, including view once and deleted photos.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _passwordField,
                        obscureText: _obscure,
                        autofocus: true,
                        enabled: !_loading,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _unlock(),
                        decoration: InputDecoration(
                          labelText: 'Admin password',
                          border: const OutlineInputBorder(),
                          errorText: _lockError,
                          errorMaxLines: 4,
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _unlock,
                          child: _loading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Open'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(AdminPhotoList list) {
    final byStatus = list.photos.where((p) => _matches(p, status: false));
    final bySender = list.photos.where((p) => _matches(p, sender: false));
    final byChat = list.photos.where((p) => _matches(p, chat: false));
    int count<T>(Iterable<AdminPhoto> photos, T Function(AdminPhoto) key, T value) =>
        photos.where((p) => key(p) == value).length;

    final statuses = [
      for (final s in PhotoStatus.values)
        // "Storage only" is rare; offer it only when there is something.
        if (s != PhotoStatus.unlinked || list.photos.any((p) => p.status == s)) s,
    ];
    // p1, p2, then files without a sender.
    final senders = {for (final p in list.photos) p.senderId ?? ''}.toList()
      ..sort((a, b) => a.isEmpty ? 1 : b.isEmpty ? -1 : a.compareTo(b));
    final chats = list.chats.where((c) => c.photoCount > 0).toList()
      ..sort((a, b) => (b.isCurrent ? 1 : 0) - (a.isCurrent ? 1 : 0));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChipRow(children: [
            _choice('All', byStatus.length, _status == null,
                () => setState(() => _status = null)),
            for (final s in statuses)
              _choice(s.label, count(byStatus, (p) => p.status, s), _status == s,
                  () => setState(() => _status = s)),
          ]),
          if (senders.length > 1) ...[
            const SizedBox(height: 8),
            _ChipRow(children: [
              _choice('Everyone', bySender.length, _sender == null,
                  () => setState(() => _sender = null)),
              for (final s in senders)
                _choice(
                    s.isEmpty ? 'Unknown' : _senderName(list, s),
                    count(bySender, (p) => p.senderId ?? '', s),
                    _sender == s,
                    () => setState(() => _sender = s)),
            ]),
          ],
          if (chats.length > 1) ...[
            const SizedBox(height: 8),
            _ChipRow(children: [
              _choice('All chats', byChat.length, _chatId == null,
                  () => setState(() => _chatId = null)),
              for (final c in chats)
                _choice(
                    c.isCurrent ? 'Current chat' : 'Old chat ${_short(c.id)}',
                    count(byChat, (p) => p.chatId, c.id),
                    _chatId == c.id,
                    () => setState(() => _chatId = c.id)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _choice(String label, int count, bool selected, VoidCallback onTap) =>
      ChoiceChip(
        label: Text('$label  $count'),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      );

  /// One heading and grid per day, newest first.
  List<Widget> _buildDays(AdminPhotoList list, List<AdminPhoto> shown) {
    final theme = Theme.of(context);
    final slivers = <Widget>[];
    var start = 0;
    while (start < shown.length) {
      final day = _day(shown[start].sentAt);
      var end = start + 1;
      while (end < shown.length && _day(shown[end].sentAt) == day) {
        end++;
      }
      final first = start;
      final photos = shown.sublist(start, end);
      slivers
        ..add(SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              '${day == null ? 'Date unknown' : formatDay(day)} · ${photos.length}',
              style: theme.textTheme.titleSmall,
            ),
          ),
        ))
        ..add(SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: photos.length,
            itemBuilder: (context, i) => _PhotoTile(
              photo: photos[i],
              name: list.nameOf(photos[i].chatId, photos[i].senderId),
              onTap: () => _open(list, shown, first + i),
            ),
          ),
        ));
      start = end;
    }
    return slivers;
  }

  void _open(AdminPhotoList list, List<AdminPhoto> shown, int index) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AdminPhotoViewerScreen(
        photos: shown,
        initialIndex: index,
        nameOf: (p) => list.nameOf(p.chatId, p.senderId),
      ),
    ));
  }

  /// A person's name; both, when old chats named them differently.
  static String _senderName(AdminPhotoList list, String senderId) {
    final names = <String>{
      for (final c in list.chats.where((c) => c.photoCount > 0))
        list.nameOf(c.id, senderId),
    };
    return names.isEmpty ? list.nameOf('', senderId) : names.join(' / ');
  }

  static DateTime? _day(DateTime? t) =>
      t == null ? null : DateTime(t.year, t.month, t.day);

  static String _short(String id) => id.length <= 6 ? id : '${id.substring(0, 6)}…';

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
}

/// Chips that wrap onto more lines when the window is narrow.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: children);
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.name, required this.onTap});

  final AdminPhoto photo;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sentAt = photo.sentAt;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          AdminPhotoImage(photo: photo, fit: BoxFit.cover, cacheWidth: 400),
          if (photo.status != PhotoStatus.chat || photo.viewOnce)
            Positioned(top: 6, left: 6, right: 6, child: Align(
              alignment: Alignment.topLeft,
              child: PhotoStatusBadge(photo: photo),
            )),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                child: Text(
                  sentAt == null ? name : '$name · ${formatTime(sentAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap),
            ),
          ),
        ],
      ),
    );
  }
}
