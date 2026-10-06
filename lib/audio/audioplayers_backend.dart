/// The only file in the game that touches an audio plugin.
///
/// Kept apart so that everything else — the board's rules, the director's
/// choices, and the tests of both — can be read and run without it.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'sound_board.dart';

class AudioplayersBackend implements SoundBackend {
  AudioplayersBackend._(this._pool);

  /// Build the players. Every plugin call is awaited here, inside one place
  /// that can fail, rather than fired off from a constructor where a failure
  /// would surface as an uncaught error with nothing above it to catch it.
  static Future<AudioplayersBackend> create() async {
    if (!kIsWeb) {
      // Ambience should mix under a phone call or another app's music, not
      // take the audio focus from whatever the player was listening to.
      await AudioPlayer.global.setAudioContext(AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
      ).build());
    }
    // A small round-robin for one-shots, so a bell does not cut off the coins
    // still ringing under it. Six is more than ever overlap.
    final pool = <AudioPlayer>[];
    for (var i = 0; i < 6; i++) {
      final p = AudioPlayer();
      // Android's low-latency path suits short sounds; the web has its own.
      if (!kIsWeb) await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setReleaseMode(ReleaseMode.stop);
      pool.add(p);
    }
    return AudioplayersBackend._(pool);
  }

  final List<AudioPlayer> _pool;
  int _next = 0;

  /// One player per loop, kept for the life of the app.
  final Map<Bed, AudioPlayer> _beds = {};

  @override
  Future<void> play(Sfx sfx, double volume) async {
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    await p.stop();
    await p.play(AssetSource(sfx.asset), volume: volume);
  }

  @override
  Future<void> startBed(Bed bed, double volume) async {
    final p = _beds[bed] ??= AudioPlayer();
    await p.setReleaseMode(ReleaseMode.loop);
    await p.play(AssetSource(bed.asset), volume: volume);
  }

  @override
  Future<void> setBed(Bed bed, double volume) async {
    await _beds[bed]?.setVolume(volume);
  }

  @override
  Future<void> pauseAll() async {
    for (final p in _beds.values) {
      await p.pause();
    }
    for (final p in _pool) {
      await p.stop();
    }
  }

  @override
  Future<void> resumeAll() async {
    for (final p in _beds.values) {
      await p.resume();
    }
  }
}
