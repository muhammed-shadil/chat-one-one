import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../services/chat_service.dart';
import '../services/voice_player.dart';
import '../theme.dart';
import '../utils/format.dart';

/// A voice message: play / pause, a waveform you can tap or drag to seek,
/// the time, and playback speed while it's playing.
class VoiceMessageContent extends StatelessWidget {
  const VoiceMessageContent({
    super.key,
    required this.message,
    required this.isMine,
    required this.chat,
    required this.meta,
  });

  final Message message;
  final bool isMine;
  final ChatService chat;

  /// Time and ticks.
  final Widget meta;

  @override
  Widget build(BuildContext context) {
    final player = VoicePlayer.instance;
    return SizedBox(
      width: 260,
      child: ValueListenableBuilder<String?>(
        valueListenable: player.current,
        builder: (context, current, _) {
          if (current != message.id) {
            return _layout(context, active: false, playing: false, position: Duration.zero);
          }
          return StreamBuilder<bool>(
            stream: player.playing,
            builder: (context, playing) => StreamBuilder<Duration>(
              stream: player.position,
              builder: (context, position) => _layout(
                context,
                active: true,
                playing: playing.data ?? false,
                position: position.data ?? Duration.zero,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _layout(
    BuildContext context, {
    required bool active,
    required bool playing,
    required Duration position,
  }) {
    final colors = ChatColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final total = message.duration;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final canPlay = message.url != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: playing ? 'Pause' : 'Play voice message',
              iconSize: 34,
              visualDensity: VisualDensity.compact,
              color: colors.meta,
              onPressed: canPlay ? _toggle : null,
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            Expanded(
              child: Waveform(
                bars: message.waveform,
                progress: active ? progress : 0,
                activeColor: isMine ? colors.seen : scheme.primary,
                idleColor: colors.meta.withValues(alpha: 0.45),
                onSeek: canPlay ? _seek : null,
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
        Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.mic,
                size: 15, color: message.played ? colors.seen : colors.meta),
            const SizedBox(width: 2),
            Text(formatDuration(active ? position : total),
                style: TextStyle(
                    fontSize: 12,
                    color: colors.meta,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            if (active) ...[const SizedBox(width: 8), const _SpeedChip()],
            const Spacer(),
            meta,
          ],
        ),
      ],
    );
  }

  Future<void> _toggle() async {
    try {
      await VoicePlayer.instance.toggle(message);
      chat.markPlayed(message);
    } catch (e) {
      chat.onError(e);
    }
  }

  Future<void> _seek(double fraction) async {
    try {
      await VoicePlayer.instance.seek(message, fraction);
      chat.markPlayed(message);
    } catch (e) {
      chat.onError(e);
    }
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip();

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final player = VoicePlayer.instance;
    return ValueListenableBuilder<double>(
      valueListenable: player.speed,
      builder: (context, speed, _) => Tooltip(
        message: 'Playback speed',
        child: InkWell(
          onTap: player.cycleSpeed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: colors.meta.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

/// Loudness bars, colored up to [progress]. Tap or drag to seek.
class Waveform extends StatelessWidget {
  const Waveform({
    super.key,
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.idleColor,
    this.onSeek,
    this.height = 30,
  });

  /// Loudness from 0 to 100. Empty draws a flat line.
  final List<int> bars;
  final double progress;
  final Color activeColor;
  final Color idleColor;
  final ValueChanged<double>? onSeek;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seek(Offset p) => onSeek?.call((p.dx / width).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onSeek == null ? null : (d) => seek(d.localPosition),
          onHorizontalDragUpdate:
              onSeek == null ? null : (d) => seek(d.localPosition),
          child: CustomPaint(
            size: Size(width, height),
            painter: _WaveformPainter(bars, progress, activeColor, idleColor),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.bars, this.progress, this.active, this.idle);

  final List<int> bars;
  final double progress;
  final Color active;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.isEmpty ? 40 : bars.length;
    final step = size.width / n;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.5, step * 0.55);
    for (var i = 0; i < n; i++) {
      final level = bars.isEmpty ? 0 : bars[i];
      final h = math.max(3.0, level / 100 * size.height);
      final x = i * step + step / 2;
      paint.color = (i + 0.5) / n <= progress ? active : idle;
      canvas.drawLine(Offset(x, (size.height - h) / 2),
          Offset(x, (size.height + h) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.bars != bars ||
      old.active != active ||
      old.idle != idle;
}
