import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/shared_location.dart';
import '../services/chat_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../utils/format.dart';

/// Where the other person was when they last shared their location (one
/// time; it never updates by itself), and whether I'm sharing mine.
///
/// My own location is only visible to them if I choose to share it here, or
/// on the surprise screen.
class SharedLocationScreen extends StatefulWidget {
  const SharedLocationScreen({
    super.key,
    required this.chat,
    this.partnerName,
    this.location = const LocationService(),
  });

  final ChatService chat;
  final String? partnerName;
  final LocationService location;

  @override
  State<SharedLocationScreen> createState() => _SharedLocationScreenState();
}

class _SharedLocationScreenState extends State<SharedLocationScreen> {
  late final _theirs = widget.chat.watchSharedLocation(widget.chat.other);
  late final _mine = widget.chat.watchSharedLocation(widget.chat.me);
  bool _sharing = false;

  String get _partner => widget.partnerName?.trim().isNotEmpty == true
      ? widget.partnerName!.trim()
      : 'The other person';

  Future<void> _openInMaps(LocationFix fix) async {
    final ok = await launchUrl(mapsUri(fix), mode: LaunchMode.externalApplication)
        .catchError((Object _) => false);
    if (!ok) _snack("Couldn't open Maps.");
  }

  Future<void> _copy(LocationFix fix) async {
    await Clipboard.setData(
        ClipboardData(text: formatCoordinates(fix.latitude, fix.longitude)));
    _snack('Coordinates copied.');
  }

  Future<void> _delete(String personId) async {
    final mine = personId == widget.chat.me;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(mine ? 'Stop sharing?' : "Delete $_partner's location?"),
        content: Text(mine
            ? '$_partner will no longer see your location. It is deleted for '
                'both of you.'
            : 'It will be deleted for both of you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(mine ? 'Stop sharing' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok == true) widget.chat.deleteSharedLocation(personId);
  }

  /// Shares my own location one time, after asking.
  Future<void> _shareMine() async {
    final retention = formatRetention(kLocationRetention);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Share your location?'),
        content: Text(
            'Your current location is shared with $_partner one time — no '
            'tracking. It is deleted automatically after $retention.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _sharing = true);
    try {
      final result = await widget.location.captureOnce();
      final fix = result.fix;
      if (fix == null) {
        final problem = result.problem!;
        _snack(problem.message,
            action: problem.canOpenSettings
                ? SnackBarAction(
                    label: problem.settingsLabel,
                    onPressed: () => widget.location.openSettingsFor(problem),
                  )
                : null);
        return;
      }
      await widget.chat.shareLocation(fix);
      _snack('Your location is shared with $_partner.');
    } on TimeoutException {
      _snack("You're offline. Your location will be shared once you're back "
          'online.');
    } catch (e) {
      debugPrint('Sharing the location failed: $e');
      _snack("Couldn't share your location. Check your connection and try "
          'again.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _snack(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary, fontWeight: FontWeight.w600);

    return Scaffold(
      appBar: AppBar(title: const Text('Shared location')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StreamBuilder<SharedLocation?>(
                    stream: _theirs,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return _InfoCard(
                          icon: Icons.cloud_off_outlined,
                          title: "Couldn't load the shared location",
                          body: '${snap.error}',
                        );
                      }
                      if (!snap.hasData &&
                          snap.connectionState != ConnectionState.done) {
                        return const _Loading();
                      }
                      final location = snap.data;
                      if (location == null) {
                        return _InfoCard(
                          icon: Icons.location_off_outlined,
                          title: "$_partner hasn't shared a location",
                          body: 'When they share it, it shows up here.',
                        );
                      }
                      return _PartnerLocation(
                        location: location,
                        name: _partner,
                        onOpenInMaps: () => _openInMaps(location.fix),
                        onCopy: () => _copy(location.fix),
                        onDelete: () => _delete(location.userId),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  Text('Your location', style: heading),
                  const SizedBox(height: 10),
                  StreamBuilder<SharedLocation?>(
                    stream: _mine,
                    builder: (context, snap) {
                      if (!snap.hasData &&
                          !snap.hasError &&
                          snap.connectionState != ConnectionState.done) {
                        return const _Loading(height: 80);
                      }
                      return _MyLocation(
                        location: snap.data,
                        partner: _partner,
                        sharing: _sharing,
                        onShare: _shareMine,
                        onStop: () => _delete(widget.chat.me),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the place in Apple Maps on iPhone, Google Maps everywhere else.
@visibleForTesting
Uri mapsUri(LocationFix fix, {TargetPlatform? platform}) {
  final at = '${fix.latitude},${fix.longitude}';
  final apple = !kIsWeb && (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  return apple
      ? Uri.https('maps.apple.com', '/', {'ll': at, 'q': at})
      : Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': at});
}

class _PartnerLocation extends StatelessWidget {
  const _PartnerLocation({
    required this.location,
    required this.name,
    required this.onOpenInMaps,
    required this.onCopy,
    required this.onDelete,
  });

  final SharedLocation location;
  final String name;
  final VoidCallback onOpenInMaps;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fix = location.fix;
    final sharedAt = location.sharedAt ?? fix.capturedAt;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 280, child: LocationMap(fix: fix)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: Text(name.characters.first.toUpperCase()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          Text('Shared ${formatMoment(sharedAt)}',
                              style: TextStyle(
                                  color: ChatColors.of(context).meta,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Detail(
                  icon: Icons.pin_drop_outlined,
                  label: 'Coordinates',
                  value: formatCoordinates(fix.latitude, fix.longitude),
                  trailing: IconButton(
                    tooltip: 'Copy coordinates',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: onCopy,
                  ),
                ),
                _Detail(
                  icon: Icons.schedule_rounded,
                  label: 'Captured',
                  value: formatMoment(fix.capturedAt),
                ),
                _Detail(
                  icon: Icons.gps_fixed_rounded,
                  label: 'Accuracy',
                  value: formatAccuracy(fix.accuracy),
                ),
                _Detail(
                  icon: Icons.auto_delete_outlined,
                  label: 'Deleted automatically',
                  value: formatMoment(location.expiresAt),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                    ),
                    FilledButton.icon(
                      onPressed: onOpenInMaps,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Open in Maps'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An OpenStreetMap map with a pin, and a circle showing the accuracy.
class LocationMap extends StatelessWidget {
  const LocationMap({super.key, required this.fix});

  final LocationFix fix;

  /// Close in when the position is precise, further out when it isn't.
  static double zoomFor(double accuracy) => switch (accuracy) {
        <= 50 => 17,
        <= 200 => 16,
        <= 1000 => 14,
        <= 5000 => 12,
        _ => 10,
      };

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final point = LatLng(fix.latitude, fix.longitude);
    return FlutterMap(
      options: MapOptions(
        initialCenter: point,
        initialZoom: zoomFor(fix.accuracy),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.chat_one_one',
        ),
        CircleLayer(circles: [
          CircleMarker(
            point: point,
            radius: fix.accuracy,
            useRadiusInMeter: true,
            color: primary.withValues(alpha: 0.15),
            borderColor: primary.withValues(alpha: 0.6),
            borderStrokeWidth: 1.5,
          ),
        ]),
        MarkerLayer(markers: [
          Marker(
            point: point,
            width: 48,
            height: 48,
            // The pin's tip, not its middle, is on the spot.
            alignment: Alignment.topCenter,
            child: Icon(
              Icons.location_on,
              size: 48,
              color: primary,
              shadows: const [Shadow(color: Colors.black38, blurRadius: 6)],
            ),
          ),
        ]),
        // Required by OpenStreetMap. flutter_map's own attribution row
        // overflows narrow phones, so this one shortens instead.
        Align(
          alignment: Alignment.bottomRight,
          child: GestureDetector(
            onTap: () => launchUrl(
                Uri.https('www.openstreetmap.org', '/copyright'),
                mode: LaunchMode.externalApplication),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.white.withValues(alpha: 0.85),
              child: const Text(
                '© OpenStreetMap contributors',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final meta = ChatColors.of(context).meta;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: meta),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: meta, fontSize: 12.5)),
                const SizedBox(height: 2),
                SelectableText(value, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _MyLocation extends StatelessWidget {
  const _MyLocation({
    required this.location,
    required this.partner,
    required this.sharing,
    required this.onShare,
    required this.onStop,
  });

  final SharedLocation? location;
  final String partner;
  final bool sharing;
  final VoidCallback onShare;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final location = this.location;
    final meta = ChatColors.of(context).meta;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              location == null
                  ? "$partner can't see your location."
                  : 'You shared your location '
                      '${formatMoment(location.sharedAt ?? location.fix.capturedAt)}.',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              location == null
                  ? 'Share it one time if you like. It is never tracked or '
                      'updated by itself.'
                  : '$partner can see it until '
                      '${formatMoment(location.expiresAt)}.',
              style: TextStyle(color: meta, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: location == null
                  ? FilledButton.tonalIcon(
                      onPressed: sharing ? null : onShare,
                      icon: sharing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location_rounded),
                      label: Text(sharing ? 'Sharing…' : 'Share my location once'),
                    )
                  : OutlinedButton.icon(
                      onPressed: onStop,
                      icon: const Icon(Icons.location_off_outlined),
                      label: const Text('Stop sharing'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: ChatColors.of(context).meta)),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({this.height = 200});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator()),
      );
}
