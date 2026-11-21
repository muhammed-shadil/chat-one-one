import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The surprise screens' own look, the same in every chat theme.
abstract final class SurpriseColors {
  static const plum = Color(0xFF2A0A3D);
  static const berry = Color(0xFF7B1E5A);
  static const rose = Color(0xFFE8457A);
  static const blush = Color(0xFFFF8FA3);
  static const peach = Color(0xFFFFC2A8);
  static const gold = Color(0xFFFFD58A);
  static const lilac = Color(0xFFC9A7FF);
}

/// True when the system asks for less motion (or in tests that set it):
/// the looping animations then stand still.
bool _still(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A heart filling [r]: two round lobes on top, a point at the bottom.
Path heartPath(Rect r) {
  final w = r.width, h = r.height, x = r.left, y = r.top;
  return Path()
    ..moveTo(x + w * 0.5, y + h * 0.27)
    ..cubicTo(x + w * 0.5, y + h * 0.02, x, y, x, y + h * 0.32)
    ..cubicTo(x, y + h * 0.6, x + w * 0.42, y + h * 0.78, x + w * 0.5, y + h)
    ..cubicTo(x + w * 0.58, y + h * 0.78, x + w, y + h * 0.6, x + w, y + h * 0.32)
    ..cubicTo(x + w, y, x + w * 0.5, y + h * 0.02, x + w * 0.5, y + h * 0.27)
    ..close();
}

// ------------------------------------------------------------ background

/// A slowly shifting plum-to-peach gradient with soft glows and hearts
/// drifting upwards behind [child].
class RomanticBackground extends StatefulWidget {
  const RomanticBackground({super.key, required this.child});

  final Widget child;

  @override
  State<RomanticBackground> createState() => _RomanticBackgroundState();
}

class _RomanticBackgroundState extends State<RomanticBackground>
    with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(
      vsync: this, duration: const Duration(seconds: 16));
  final _hearts = _DriftingHeart.scatter(18, math.Random(14));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, child) {
        final sway = math.sin(_loop.value * 2 * math.pi);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + 0.5 * sway, -1),
              end: Alignment(1 - 0.5 * sway, 1),
              colors: const [
                SurpriseColors.plum,
                SurpriseColors.berry,
                SurpriseColors.rose,
                SurpriseColors.peach,
              ],
              stops: const [0, 0.45, 0.8, 1],
            ),
          ),
          child: CustomPaint(
            painter: _BackgroundPainter(_hearts, _loop.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _DriftingHeart {
  const _DriftingHeart(
      this.x, this.size, this.laps, this.phase, this.sway, this.opacity);

  /// Across the screen, 0–1.
  final double x;
  final double size;

  /// Whole trips up the screen per loop, so the loop has no visible seam.
  final int laps;
  final double phase;
  final double sway;
  final double opacity;

  static List<_DriftingHeart> scatter(int count, math.Random r) => [
        for (var i = 0; i < count; i++)
          _DriftingHeart(
            (i + r.nextDouble()) / count,
            10 + r.nextDouble() * 22,
            1 + r.nextInt(3),
            r.nextDouble(),
            8 + r.nextDouble() * 22,
            0.12 + r.nextDouble() * 0.28,
          ),
      ];
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.hearts, this.t);

  final List<_DriftingHeart> hearts;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final angle = t * 2 * math.pi;
    // Big soft glows that wander a little.
    for (final (cx, cy, r, color) in [
      (0.2 + 0.08 * math.sin(angle), 0.18, 0.55, SurpriseColors.lilac),
      (0.85, 0.5 + 0.06 * math.cos(angle), 0.5, SurpriseColors.blush),
      (0.3 + 0.06 * math.cos(angle), 0.92, 0.6, SurpriseColors.gold),
    ]) {
      final center = Offset(cx * size.width, cy * size.height);
      final radius = r * size.shortestSide;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: 0.32),
            color.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    for (final h in hearts) {
      final p = (t * h.laps + h.phase) % 1;
      final y = size.height * (1.08 - p * 1.2);
      final x = h.x * size.width + math.sin((p + h.phase) * 2 * math.pi) * h.sway;
      // Fade in at the bottom and out near the top.
      final fade = math.min(1.0, math.min(p / 0.15, (1 - p) / 0.3));
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(math.sin((p + h.phase) * 2 * math.pi) * 0.3);
      canvas.drawPath(
        heartPath(Rect.fromCenter(
            center: Offset.zero, width: h.size, height: h.size * 0.9)),
        Paint()..color = Colors.white.withValues(alpha: h.opacity * fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.t != t;
}

// ----------------------------------------------------------------- glass

/// Frosted glass: blurs what's behind it, with a light edge and sheen.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 28, 24, 20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  static const _radius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(
            color: SurpriseColors.plum.withValues(alpha: 0.35),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: _radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.24),
                  Colors.white.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.38), width: 1.2),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- floating

/// Gently bobs [child] up and down.
class Floating extends StatefulWidget {
  const Floating({
    super.key,
    required this.child,
    this.distance = 10,
    this.period = const Duration(milliseconds: 3600),
  });

  final Widget child;
  final double distance;
  final Duration period;

  @override
  State<Floating> createState() => _FloatingState();
}

class _FloatingState extends State<Floating>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period);
  late final _curve = CurvedAnimation(parent: _c, curve: Curves.easeInOutSine);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.distance * (0.5 - _curve.value)),
          child: child,
        ),
        child: widget.child,
      );
}

// ---------------------------------------------------------------- badge

/// A round glass badge with ripples spreading out from it, and optionally
/// twinkling sparkles around it.
class GlowBadge extends StatefulWidget {
  const GlowBadge({
    super.key,
    required this.size,
    required this.child,
    this.sparkles = false,
  });

  final double size;
  final Widget child;
  final bool sparkles;

  @override
  State<GlowBadge> createState() => _GlowBadgeState();
}

class _GlowBadgeState extends State<GlowBadge>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inner = widget.size * 0.6;
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _RipplePainter(_c, sparkles: widget.sparkles),
        child: Center(
          child: Container(
            width: inner,
            height: inner,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.38),
                  Colors.white.withValues(alpha: 0.1),
                ],
              ),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: SurpriseColors.rose.withValues(alpha: 0.55),
                  blurRadius: 36,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.animation, {required this.sparkles})
      : super(repaint: animation);

  final Animation<double> animation;
  final bool sparkles;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final center = size.center(Offset.zero);
    final half = size.shortestSide / 2;

    for (final offset in [0.0, 0.5]) {
      final p = (t + offset) % 1;
      canvas.drawCircle(
        center,
        half * (0.6 + 0.4 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.45 * (1 - p)),
      );
    }

    if (!sparkles) return;
    for (var i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / 5 + 0.35;
      final at = center + Offset(math.cos(angle), math.sin(angle)) * half * 0.9;
      final twinkle = math.sin((t + i / 5) * 2 * math.pi).abs();
      _star(canvas, at, 4 + 5 * twinkle,
          Paint()..color = Colors.white.withValues(alpha: 0.35 + 0.6 * twinkle));
    }
  }

  /// A four-pointed sparkle.
  static void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final w = r * 0.28;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.sparkles != sparkles;
}

/// A glossy pink heart, with an optional [child] (e.g. a tick) on it.
class GradientHeart extends StatelessWidget {
  const GradientHeart({super.key, required this.size, this.child});

  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size * 0.92),
        painter: const _GradientHeartPainter(),
        child: SizedBox(
          width: size,
          height: size * 0.92,
          // The heart's middle is above its box's middle (lobes vs. point).
          child: Align(alignment: const Alignment(0, -0.2), child: child),
        ),
      );
}

class _GradientHeartPainter extends CustomPainter {
  const _GradientHeartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = heartPath(rect);
    canvas.drawShadow(path, SurpriseColors.berry, 6, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SurpriseColors.blush, SurpriseColors.rose, SurpriseColors.berry],
        ).createShader(rect),
    );
    // Shine on the left lobe.
    canvas.drawOval(
      Rect.fromLTWH(size.width * 0.14, size.height * 0.12, size.width * 0.22,
          size.height * 0.14),
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(_GradientHeartPainter old) => false;
}

// --------------------------------------------------------------- button

/// The main call to action: a glowing white pill.
class SurpriseButton extends StatelessWidget {
  const SurpriseButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busyLabel,
  });

  final String label;
  final IconData? icon;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// Shown with a spinner, instead of [label], while working.
  final String? busyLabel;

  static const _radius = BorderRadius.all(Radius.circular(30));

  @override
  Widget build(BuildContext context) {
    final busy = busyLabel != null;
    final enabled = onPressed != null && !busy;
    const textColor = SurpriseColors.berry;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled || busy ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _radius,
          boxShadow: [
            BoxShadow(
              color: SurpriseColors.rose.withValues(alpha: 0.5),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: const BoxDecoration(
              borderRadius: _radius,
              gradient: LinearGradient(
                colors: [Colors.white, Color(0xFFFFE2EB)],
              ),
            ),
            child: InkWell(
              borderRadius: _radius,
              onTap: enabled ? onPressed : null,
              splashColor: SurpriseColors.blush.withValues(alpha: 0.3),
              child: SizedBox(
                height: 56,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      key: ValueKey(busy),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (busy)
                          const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: textColor),
                          )
                        else if (icon != null)
                          Icon(icon, color: textColor, size: 22),
                        if (busy || icon != null) const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            busyLabel ?? label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
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
      ),
    );
  }
}

// -------------------------------------------------------------- confetti

/// One burst of confetti and little hearts that rains down and fades.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    this.count = 120,
    this.duration = const Duration(milliseconds: 3800),
  });

  final int count;
  final Duration duration;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration);
  late final _pieces = _Piece.burst(widget.count, math.Random());
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!_still(context)) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_c, _pieces,
              widget.duration.inMilliseconds / 1000),
        ),
      );
}

class _Piece {
  const _Piece(this.angle, this.speed, this.size, this.spin, this.flutter,
      this.shape, this.color, this.delay);

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final double flutter;

  /// 0 strip, 1 dot, 2 heart.
  final int shape;
  final Color color;
  final double delay;

  static const _colors = [
    SurpriseColors.gold,
    Colors.white,
    SurpriseColors.blush,
    SurpriseColors.rose,
    SurpriseColors.peach,
    SurpriseColors.lilac,
  ];

  static List<_Piece> burst(int count, math.Random r) => [
        for (var i = 0; i < count; i++)
          _Piece(
            // Mostly upwards, fanning out to both sides.
            -math.pi / 2 + (r.nextDouble() - 0.5) * 2.6,
            520 + r.nextDouble() * 780,
            6 + r.nextDouble() * 7,
            (r.nextDouble() - 0.5) * 12,
            4 + r.nextDouble() * 8,
            r.nextInt(3),
            _colors[r.nextInt(_colors.length)],
            r.nextDouble() * 0.18,
          ),
      ];
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.animation, this.pieces, this.seconds)
      : super(repaint: animation);

  final Animation<double> animation;
  final List<_Piece> pieces;
  final double seconds;

  static const _gravity = 560.0, _drag = 1.9;

  @override
  void paint(Canvas canvas, Size size) {
    if (animation.status == AnimationStatus.dismissed) return;
    final now = animation.value * seconds;
    final origin = Offset(size.width / 2, size.height * 0.3);
    // Small screens get a smaller burst.
    final scale = (size.shortestSide / 420).clamp(0.6, 1.3);
    final fade = animation.value < 0.7 ? 1.0 : (1 - animation.value) / 0.3;
    final paint = Paint();

    for (final p in pieces) {
      final t = now - p.delay;
      if (t <= 0) continue;
      // Thrown out against air resistance, then falling at a gentle pace.
      final slow = (1 - math.exp(-_drag * t)) / _drag;
      final vx = math.cos(p.angle) * p.speed * scale;
      final vy = math.sin(p.angle) * p.speed * scale;
      const terminal = _gravity / _drag;
      final at = origin +
          Offset(vx * slow, terminal * t + (vy - terminal) * slow);
      if (at.dy > size.height + 20) continue;

      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(p.spin * t)
        // Turning over in the air.
        ..scale(math.max(0.25, math.cos(p.flutter * t).abs()), 1);
      final s = p.size;
      switch (p.shape) {
        case 0:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.5),
                const Radius.circular(1.5)),
            paint,
          );
        case 1:
          canvas.drawCircle(Offset.zero, s * 0.38, paint);
        default:
          canvas.drawPath(
            heartPath(Rect.fromCenter(
                center: Offset.zero, width: s * 1.2, height: s * 1.1)),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
