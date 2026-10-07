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

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Short sounds, played once.
enum Sfx {
  bell(0.7, 800),
  coins(0.55, 120),
  hammer(0.7, 200),
  cannon(0.85, 400),
  thunder(0.75, 3000),
  // Three calls, and quieter than they were: the first gull was one call
  // played every time, too loud and too clean — "birds sound a little odd".
  // Out over the water, and never the same twice running.
  gull(0.32, 4000, variants: 3),
  chime(0.9, 2000),
  alarm(0.7, 1500);

  const Sfx(this.volume, this.minGapMs, {this.variants = 1});

  /// Where it sits in the mix, before anything else scales it.
  final double volume;

  /// The least time between two of these. Selling ten lots in a second
  /// should sound like trade, not a slot machine paying out.
  final int minGapMs;

  /// How many different takes of this sound there are. A sound that repeats
  /// exactly is the quickest way to give away that it is not real.
  final int variants;

  /// The file for take [i]: `gull.wav`, then `gull_2.wav`, `gull_3.wav`.
  String assetFor(int i) =>
      i == 0 ? 'sounds/$name.wav' : 'sounds/${name}_${i + 1}.wav';

  String get asset => assetFor(0);
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
  Future<void> play(Sfx sfx, double volume, {int variant = 0});
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
  /// Loops that have actually started. Per loop, and only on success.
  ///
  /// IT USED TO BE ONE FLAG, set before anything had played. The loops were
  /// started once, in order, on the first touch; a start that failed was
  /// caught, logged and never tried again, so a single bad start would have
  /// left that loop silent for the whole session while the others played on.
  /// Now a loop that has not started is tried again on the next touch.
  ///
  /// Found while chasing a run that "haven't really heard any waves" — and
  /// NOT the cause of it: driven in a real browser, every loop started first
  /// time. The sea was playing, and did not sound like the sea; see
  /// tool/make_sounds.py. The gap was real all the same.
  final Set<Bed> _started = {};
  final Map<Sfx, int> _lastPlayed = {};
  final Map<Sfx, int> _lastVariant = {};
  final math.Random _random = math.Random();

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

  /// A touch. The first one unlocks sound — see the library note — and every
  /// one after gives any loop that failed to start another chance.
  void unlock() {
    if (_unlocked) {
      if (_started.length < Bed.values.length && audible) _startMissing();
      return;
    }
    _unlocked = true;
    _apply();
  }

  Future<void> _startMissing() async {
    final b = _backend;
    if (b == null) return;
    for (final bed in Bed.values) {
      if (_started.contains(bed)) continue;
      try {
        await b.startBed(bed, _beds[bed]!);
        _started.add(bed);
      } catch (e) {
        debugPrint('sound: $bed would not start: $e');
      }
    }
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
    _guard(b.play(sfx, (sfx.volume * volume).clamp(0.0, 1.0),
        variant: _pickVariant(sfx)));
  }

  /// A take of [sfx], never the one played last time if there is a choice.
  int _pickVariant(Sfx sfx) {
    if (sfx.variants <= 1) return 0;
    final last = _lastVariant[sfx];
    var v = _random.nextInt(sfx.variants);
    if (v == last) v = (v + 1 + _random.nextInt(sfx.variants - 1)) % sfx.variants;
    _lastVariant[sfx] = v;
    return v;
  }

  /// Set how loud each ambient loop should be, 0 to 1.
  void setBeds(Map<Bed, double> levels) {
    _beds.addAll(levels);
    final b = _backend;
    if (b == null || !audible) return;
    for (final e in levels.entries) {
      if (_started.contains(e.key)) _guard(b.setBed(e.key, e.value));
    }
  }

  Future<void> _apply() async {
    final b = _backend;
    if (b == null) return;
    if (!audible) {
      await _guard(b.pauseAll());
      return;
    }
    if (_started.isNotEmpty) {
      await _guard(b.resumeAll());
      for (final e in _beds.entries) {
        if (_started.contains(e.key)) await _guard(b.setBed(e.key, e.value));
      }
    }
    await _startMissing();
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
    _started.clear();
    _lastPlayed.clear();
    _lastVariant.clear();
    clock = _wallClock;
    for (final b in Bed.values) {
      _beds[b] = 0;
    }
    muted.value = false;
  }
}
