import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/message.dart';

/// Plays voice messages, one at a time, for every bubble in the chat.
class VoicePlayer {
  VoicePlayer._() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // Back to the start, ready to play again, like other chat apps.
        current.value = null;
        _player
          ..pause()
          ..seek(Duration.zero);
      }
    });
  }

  static final instance = VoicePlayer._();

  final _player = AudioPlayer();

  /// The message that is loaded (playing or paused), if any.
  final current = ValueNotifier<String?>(null);

  /// Playback speed: 1×, 1.5× or 2×.
  final speed = ValueNotifier<double>(1);

  Stream<Duration> get position => _player.positionStream;
  Stream<bool> get playing => _player.playingStream;

  /// Plays [m], or pauses / resumes it if it's the one already loaded.
  Future<void> toggle(Message m) async {
    if (current.value == m.id) {
      _player.playing ? await _player.pause() : _player.play().ignore();
      return;
    }
    final url = m.url;
    if (url == null) return;
    await _player.stop();
    current.value = m.id;
    try {
      await _player.setUrl(url);
    } catch (_) {
      current.value = null;
      rethrow;
    }
    await _player.setSpeed(speed.value);
    // play() only completes when playback stops, so don't wait for it.
    _player.play().ignore();
  }

  /// Jumps to [fraction] (0–1) of [m], starting it first if needed.
  Future<void> seek(Message m, double fraction) async {
    if (current.value != m.id) await toggle(m);
    await _player.seek(m.duration * fraction.clamp(0.0, 1.0));
  }

  void cycleSpeed() {
    speed.value = switch (speed.value) { 1 => 1.5, 1.5 => 2, _ => 1 };
    _player.setSpeed(speed.value);
  }

  Future<void> stop() async {
    current.value = null;
    await _player.stop();
  }
}
