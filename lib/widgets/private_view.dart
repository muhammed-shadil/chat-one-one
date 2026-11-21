import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Hides photos on the website while the window isn't in focus.
///
/// On Android the whole app already blocks screenshots and screen recording
/// (FLAG_SECURE in MainActivity). Browsers can't block them, so this covers
/// the photo whenever the window loses focus or the tab is hidden, e.g. when
/// switching to a screenshot or recording app. Elsewhere it shows [child].
class PrivateView extends StatefulWidget {
  const PrivateView({super.key, required this.child});

  final Widget child;

  @override
  State<PrivateView> createState() => _PrivateViewState();
}

class _PrivateViewState extends State<PrivateView> {
  AppLifecycleListener? _listener;
  bool _away = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    final state = WidgetsBinding.instance.lifecycleState;
    _away = state != null && state != AppLifecycleState.resumed;
    _listener = AppLifecycleListener(
      onStateChange: (state) =>
          setState(() => _away = state != AppLifecycleState.resumed),
    );
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the photo loaded (a view-once photo can't be fetched again),
        // but don't draw it while away.
        Visibility.maintain(visible: !_away, child: widget.child),
        if (_away)
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_off_outlined,
                        color: Colors.white54, size: 48),
                    SizedBox(height: 12),
                    Text(
                      'Photo hidden while this window is in the background',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
