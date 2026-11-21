import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/chat_service.dart';
import '../services/location_service.dart';
import '../utils/format.dart';
import '../widgets/surprise_effects.dart';

/// The surprise: an invitation, then a clear choice to share the current
/// location one time, then a celebration.
///
/// Nothing touches the location until "Share My Location" is tapped. Then
/// permission is asked for (only if it hasn't been given yet), the position
/// is read once, and saved with [ChatService.shareLocation]. There is no
/// tracking: closing this screen ends it.
class SurpriseScreen extends StatefulWidget {
  const SurpriseScreen({
    super.key,
    required this.chat,
    this.partnerName,
    this.location = const LocationService(),
  });

  final ChatService chat;

  /// Who will be able to see the location.
  final String? partnerName;
  final LocationService location;

  /// Fades and grows in over the chat.
  static Route<void> route({
    required ChatService chat,
    String? partnerName,
    LocationService location = const LocationService(),
  }) =>
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 550),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => SurpriseScreen(
            chat: chat, partnerName: partnerName, location: location),
        transitionsBuilder: (_, animation, _, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 0.94, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      );

  @override
  State<SurpriseScreen> createState() => _SurpriseScreenState();
}

enum _Stage { invite, consent, success }

class _SurpriseScreenState extends State<SurpriseScreen> {
  _Stage _stage = _Stage.invite;

  /// Non-null while finding or sending the location.
  String? _busy;
  LocationProblem? _problem;
  String? _sendError;

  /// Saved on the phone but not on the server yet (offline).
  bool _queued = false;

  String get _partner => widget.partnerName?.trim().isNotEmpty == true
      ? widget.partnerName!.trim()
      : 'the other person';

  void _close() => Navigator.of(context).maybePop();

  Future<void> _share() async {
    if (_busy != null) return;
    setState(() {
      _busy = 'Finding your location…';
      _problem = null;
      _sendError = null;
    });

    final result = await widget.location.captureOnce();
    if (!mounted) return;
    final fix = result.fix;
    if (fix == null) {
      setState(() {
        _busy = null;
        _problem = result.problem;
      });
      return;
    }

    setState(() => _busy = 'Sharing…');
    var queued = false;
    try {
      await widget.chat.shareLocation(fix);
    } on TimeoutException {
      // Firestore keeps it and sends it once the phone is back online.
      queued = true;
    } catch (e) {
      debugPrint('Sharing the location failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = null;
        _sendError =
            "Couldn't share your location. Check your connection and try again.";
      });
      return;
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact().ignore();
    setState(() {
      _busy = null;
      _queued = queued;
      _stage = _Stage.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final badge = (size.height * 0.2).clamp(112.0, 168.0);

    return PopScope(
      // Don't leave halfway through sending.
      canPop: _busy == null,
      child: Scaffold(
        backgroundColor: SurpriseColors.plum,
        body: RomanticBackground(
          child: Stack(
            children: [
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        reverseDuration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: _stageTransition,
                        child: switch (_stage) {
                          _Stage.invite => _invite(badge),
                          _Stage.consent => _consent(badge),
                          _Stage.success => _success(badge),
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (_stage == _Stage.success)
                const Positioned.fill(
                  child: IgnorePointer(child: ConfettiBurst()),
                ),
              if (_stage != _Stage.success)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: IconButton(
                        tooltip: 'Close',
                        onPressed: _busy == null ? _close : null,
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _stageTransition(Widget child, Animation<double> animation) =>
      FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.05), end: Offset.zero)
              .animate(animation),
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(animation),
            child: child,
          ),
        ),
      );

  // ---------------------------------------------------------------- stages

  Widget _invite(double badge) => _StageLayout(
        key: const ValueKey(_Stage.invite),
        art: Floating(
          child: GlowBadge(
            size: badge,
            sparkles: true,
            child: GradientHeart(size: badge * 0.34),
          ),
        ),
        // A no-break space keeps the heart with the last word.
        title: 'A Little Surprise Awaits ❤️',
        body: "Let's make a little memory together. There's something special "
            'waiting for you!',
        children: [
          const SizedBox(height: 28),
          SurpriseButton(
            label: 'Discover Now ❤️',
            onPressed: () => setState(() => _stage = _Stage.consent),
          ),
          const SizedBox(height: 4),
        ],
      );

  Widget _consent(double badge) {
    final problem = _problem;
    final error = problem?.message ?? _sendError;
    return _StageLayout(
      key: const ValueKey(_Stage.consent),
      art: Floating(
        child: GlowBadge(
          size: badge,
          child: Icon(Icons.location_on_rounded,
              color: Colors.white, size: badge * 0.3),
        ),
      ),
      title: 'Share Your Current Location',
      body: 'Share your current location once so we can stay connected.',
      children: [
        const SizedBox(height: 20),
        const _Promise(
          icon: Icons.my_location_rounded,
          text: 'Shared one time only — no tracking',
        ),
        _Promise(
          icon: Icons.lock_rounded,
          text: 'Only $_partner can see it',
        ),
        _Promise(
          icon: Icons.auto_delete_rounded,
          text: 'Deleted automatically after '
              '${formatRetention(kLocationRetention)}',
        ),
        const SizedBox(height: 24),
        SurpriseButton(
          label: 'Share My Location',
          icon: Icons.favorite_rounded,
          busyLabel: _busy,
          onPressed: _share,
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _busy == null ? _close : null,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white38,
            minimumSize: const Size.fromHeight(46),
          ),
          child: const Text('Maybe Later',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: error == null
              ? const SizedBox(width: double.infinity)
              : _Notice(
                  message: error,
                  actionLabel: problem != null && problem.canOpenSettings
                      ? problem.settingsLabel
                      : null,
                  onAction: () => widget.location.openSettingsFor(problem!),
                ),
        ),
      ],
    );
  }

  Widget _success(double badge) => _StageLayout(
        key: const ValueKey(_Stage.success),
        art: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: math.max(0, scale), child: child),
          child: GlowBadge(
            size: badge,
            sparkles: true,
            child: GradientHeart(
              size: badge * 0.4,
              child: Icon(Icons.check_rounded,
                  color: Colors.white, size: badge * 0.2),
            ),
          ),
        ),
        title: 'Successfully Connected! ❤️',
        body: _queued
            ? "You're offline right now. Your location will be shared as soon "
                "as you're back online."
            : 'Your location has been shared successfully.',
        children: [
          const SizedBox(height: 28),
          SurpriseButton(label: 'Continue Chatting', onPressed: _close),
          const SizedBox(height: 4),
        ],
      );
}

/// Picture on top, then a glass card with the title, text and buttons.
class _StageLayout extends StatelessWidget {
  const _StageLayout({
    super.key,
    required this.art,
    required this.title,
    required this.body,
    required this.children,
  });

  final Widget art;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        art,
        const SizedBox(height: 22),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.3,
                  shadows: [
                    Shadow(color: Color(0x552A0A3D), blurRadius: 12),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              ...children,
            ],
          ),
        ),
      ],
    );
  }
}

/// One line of what sharing means, with an icon.
class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
            ),
            child: Icon(icon, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Why it didn't work, and the setting that would fix it.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: SurpriseColors.plum.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: SurpriseColors.gold, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  shape: const StadiumBorder(),
                ),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
