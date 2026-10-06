/// What the game can play, and the one place that decides whether it does.
///
/// Three rules live here and nowhere else:
///
/// - NOTHING PLAYS UNTIL main() SAYS SO. A widget test pumps the whole app
///   without ever calling the app's main(), so the board stays without a
///   backend and every call is a no-op — no test can reach for an audio plugin
///   that does not exist in a test runner. The same rule the world view's
///   animation clock follows, for the same reason.
/// - NOTHING PLAYS BEFORE THE FIRST TOUCH. A browser refuses to start audio
///   until the player has interacted with the page, and an attempt before then
///   fails. The rule is applied on every platform, so there is one behaviour
///   to reason about; on a phone the first touch is a moment after launch.
/// - MUTE IS REMEMBERED, and it silences everything, ambience included.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Short sounds, played once.
enum Sfx {
  bell(0.7, 800),
  coins(0.55, 120),
  hammer(0.7, 200),
  cannon(0.85, 400),
  thunder(0.75, 3000),
  gull(0.45, 4000),
  chime(0.9, 2000),
  alarm(0.7, 1500);

  const Sfx(this.volume, this.minGapMs);

  /// Where it sits in the mix, before anything else scales it.
  final double volume;

  /// The least time between two of these. Selling ten lots in a second
  /// should sound like trade, not a slot machine paying out.
  final int minGapMs;

  String get asset => 'sounds/$name.wav';
}

/// Sounds that loop for as long as they are wanted, at a varying level.
enum Bed {
  sea,
  wind,
  rain;

  String get asset => 'sounds/$name.wav';
}

/// What actually makes the noise. One real one, in audioplayers_backend.dart;
/// tests substitute one that writes down what it was asked to do.
abstract class SoundBackend {
  Future<void> play(Sfx sfx, double volume);
  Future<void> startBed(Bed bed, double volume);
  Future<void> setBed(Bed bed, double volume);
  Future<void> pauseAll();
  Future<void> resumeAll();
}

class SoundBoard {
  SoundBoard._();
  static final SoundBoard instance = SoundBoard._();

  static const String _mutedKey = 'sound_muted';

  SoundBackend? _backend;
  bool _unlocked = false;
  bool _away = false;
  bool _bedsStarted = false;
  final Map<Sfx, int> _lastPlayed = {};

  /// Milliseconds, for the rate limits. A test sets its own, so that two
  /// events it means to be minutes apart are not a millisecond apart.
  @visibleForTesting
  int Function() clock = _wallClock;
  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;
  final Map<Bed, double> _beds = {for (final b in Bed.values) b: 0};

  /// Read by the HUD's speaker button.
  final ValueNotifier<bool> muted = ValueNotifier(false);

  /// Whether main() has switched sound on. Nothing that runs on a timer —
  /// the director's ambient beat — should exist until it has, or every widget
  /// test would end with a timer still pending.
  bool get enabled => _backend != null;

  /// Whether anything can be heard at all right now.
  bool get audible => _backend != null && _unlocked && !_away && !muted.value;

  /// Switch sound on. Called from main() and nowhere else.
  Future<void> init(SoundBackend backend) async {
    _backend = backend;
    await loadPreference();
  }

  Future<void> loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      muted.value = prefs.getBool(_mutedKey) ?? false;
    } catch (_) {
      // A preference that cannot be read leaves sound on, which is the
      // default the player was promised.
    }
  }

  Future<void> toggleMute() async {
    muted.value = !muted.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_mutedKey, muted.value);
    } catch (_) {}
    await _apply();
  }

  /// The first touch. See the library note.
  void unlock() {
    if (_unlocked) return;
    _unlocked = true;
    _apply();
  }

  /// The app has gone to the background, or come back. A game that kept
  /// playing the sea from a pocket would be uninstalled by lunchtime.
  void setAway(bool away) {
    if (_away == away) return;
    _away = away;
    _apply();
  }

  /// Play a sound once, if anything is audible and it is not too soon after
  /// the last one of its kind. [volume] scales its place in the mix.
  void play(Sfx sfx, {double volume = 1, int? nowMs}) {
    final b = _backend;
    if (b == null || !audible) return;
    final now = nowMs ?? clock();
    final last = _lastPlayed[sfx];
    if (last != null && now - last < sfx.minGapMs) return;
    _lastPlayed[sfx] = now;
    _guard(b.play(sfx, (sfx.volume * volume).clamp(0.0, 1.0)));
  }

  /// Set how loud each ambient loop should be, 0 to 1.
  void setBeds(Map<Bed, double> levels) {
    _beds.addAll(levels);
    final b = _backend;
    if (b == null || !audible || !_bedsStarted) return;
    for (final e in levels.entries) {
      _guard(b.setBed(e.key, e.value));
    }
  }

  Future<void> _apply() async {
    final b = _backend;
    if (b == null) return;
    if (!audible) {
      await _guard(b.pauseAll());
      return;
    }
    if (!_bedsStarted) {
      _bedsStarted = true;
      for (final bed in Bed.values) {
        await _guard(b.startBed(bed, _beds[bed]!));
      }
    } else {
      await _guard(b.resumeAll());
      for (final e in _beds.entries) {
        await _guard(b.setBed(e.key, e.value));
      }
    }
  }

  /// Sound is never worth a crash. A device with no audio output, a browser
  /// that changed its mind about autoplay, a file the player replaced with
  /// something it cannot decode: the game carries on in silence.
  Future<void> _guard(Future<void> f) async {
    try {
      await f;
    } catch (e) {
      debugPrint('sound: $e');
    }
  }

  /// Back to the state the app starts in, for a test.
  @visibleForTesting
  void reset() {
    _backend = null;
    _unlocked = false;
    _away = false;
    _bedsStarted = false;
    _lastPlayed.clear();
    clock = _wallClock;
    for (final b in Bed.values) {
      _beds[b] = 0;
    }
    muted.value = false;
  }
}
