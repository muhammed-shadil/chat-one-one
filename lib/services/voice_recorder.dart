import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A finished recording, ready to send.
class VoiceNote {
  const VoiceNote({
    required this.bytes,
    required this.mimeType,
    required this.extension,
    required this.duration,
    required this.waveform,
  });

  final Uint8List bytes;
  final String mimeType;
  final String extension;
  final Duration duration;

  /// Loudness bars from 0 to 100.
  final List<int> waveform;
}

/// Records voice messages: AAC (.m4a) on phones and in browsers that support
/// it, which all players can handle; Opus (.webm) in other browsers.
class VoiceRecorder {
  /// Recordings shorter than this are treated as a slip and dropped.
  static const minDuration = Duration(seconds: 1);

  final _recorder = AudioRecorder();
  final _samples = <double>[];
  final _clock = Stopwatch();
  StreamSubscription<Amplitude>? _amplitude;
  Timer? _ticker;
  var _mimeType = 'audio/mp4';
  var _extension = 'm4a';

  /// Time recorded so far, for the timer on screen.
  final elapsed = ValueNotifier(Duration.zero);

  /// The most recent loudness levels (0–1), newest last, for the live waveform.
  final levels = ValueNotifier<List<double>>(const []);

  /// Starts recording. Returns false if the microphone isn't allowed.
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;

    var encoder = AudioEncoder.aacLc;
    _mimeType = 'audio/mp4';
    _extension = 'm4a';
    if (kIsWeb && !await _recorder.isEncoderSupported(encoder)) {
      encoder = AudioEncoder.opus;
      _mimeType = 'audio/webm';
      _extension = 'webm';
    }
    final path = kIsWeb
        ? ''
        : '${(await getTemporaryDirectory()).path}/voice_'
            '${DateTime.now().millisecondsSinceEpoch}.$_extension';
    await _recorder.start(
      RecordConfig(encoder: encoder, numChannels: 1, bitRate: 64000),
      path: path,
    );

    _samples.clear();
    levels.value = const [];
    _clock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 200),
        (_) => elapsed.value = _clock.elapsed);
    _amplitude = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) {
      // Decibels: about -45 is a quiet room and 0 the loudest possible.
      final level = ((a.current + 45) / 45).clamp(0.0, 1.0);
      final value = level.isFinite ? level : 0.0;
      _samples.add(value);
      final recent = levels.value;
      levels.value = [
        ...recent.length >= 40 ? recent.skip(1) : recent,
        value,
      ];
    });
    return true;
  }

  /// Stops recording and returns it, or null if it was too short to keep.
  Future<VoiceNote?> stop() async {
    final duration = _clock.elapsed;
    _halt();
    final path = await _recorder.stop();
    if (path == null) return null;
    try {
      if (duration < minDuration) return null;
      return VoiceNote(
        bytes: await XFile(path).readAsBytes(),
        mimeType: _mimeType,
        extension: _extension,
        duration: duration,
        waveform: _bars(48),
      );
    } finally {
      if (!kIsWeb) File(path).delete().ignore();
    }
  }

  /// Stops recording and throws it away.
  Future<void> cancel() async {
    _halt();
    await _recorder.cancel();
  }

  Future<void> dispose() async {
    _halt();
    elapsed.dispose();
    levels.dispose();
    await _recorder.dispose();
  }

  void _halt() {
    _clock.stop();
    _ticker?.cancel();
    _amplitude?.cancel();
    elapsed.value = Duration.zero;
  }

  /// Squeezes the loudness samples into [count] bars from 0 to 100, keeping
  /// the peak of each stretch so short syllables still show. The loudest bar
  /// is scaled to 100: browsers measure loudness lower than phones do, and
  /// this makes waveforms look alike wherever they were recorded.
  List<int> _bars(int count) {
    final n = _samples.length;
    if (n == 0) return List.filled(count, 0);
    final peaks = List.generate(count, (i) {
      final start = i * n ~/ count;
      final end = math.max(start + 1, (i + 1) * n ~/ count);
      return _samples.sublist(start, math.min(end, n)).reduce(math.max);
    });
    final loudest = peaks.reduce(math.max);
    if (loudest == 0) return List.filled(count, 0);
    return [for (final p in peaks) (p / loudest * 100).round()];
  }
}
