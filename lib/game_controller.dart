import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim/game_state.dart';
import 'sim/profile.dart';

/// Drives the simulation clock and owns persistence.
///
/// Speed is a free control, including the fastest setting. In a game funded by
/// timers this is the thing you would sell; here it is a button, and the
/// difficulty lives in allocation instead of waiting.
class GameController extends ChangeNotifier {
  GameController({this.seedOverride});

  /// Pins the world a new run draws, for tests and for the store screenshots.
  ///
  /// Real play wants a different port every time; a golden test wants the same
  /// one forever. Without this the screenshot suite compares a fresh random
  /// world against a recorded image and fails at random.
  final int? seedOverride;

  static const String _saveKey = 'ports_ahoy_save_v1';
  static const String _savedAtKey = 'ports_ahoy_saved_at_ms';
  static const String _hintsKey = 'ports_ahoy_dismissed_hints';

  /// Stored apart from the save: this is what survives starting a new run.
  static const String _profileKey = 'ports_ahoy_profile';

  /// Game-hours per real second at 1×.
  ///
  /// Set by playing, not by guessing.
  ///
  /// 1.0 was far too quick to follow. 0.35 read as sluggish at 1×. The pace
  /// that actually felt right in a real session was 2× of 0.35 — so that rate,
  /// 0.70, is now what 1× gives you. A comfortable default should not be
  /// something the player has to reach for.
  static const double baseTicksPerSecond = 0.70;

  /// Time away resolves at the same rate as time watched, regardless of the
  /// speed you left on — so the world runs at one pace and nothing about
  /// closing the app is worth gaming.
  static const double offlineTicksPerSecond = baseTicksPerSecond;

  /// Multipliers offered, paused first. A half step exists because 1× is now
  /// tuned to a comfortable pace rather than a slow one, and someone who wants
  /// to watch the port more closely needs somewhere to go.
  static const List<double> speeds = [0, 0.5, 1, 2, 4];

  late GameState state;
  double speed = 1;
  bool ready = false;

  /// Ticks caught up on the last resume, for the "while you were away" card.
  int lastCatchUpTicks = 0;

  /// Hints the player has already read. Nothing is gated behind these.
  Set<String> dismissedHints = {};

  /// Charters earned, charters in force, and the record of finished runs.
  Profile profile = Profile();

  Timer? _timer;
  double _accumulator = 0;
  static const Duration _frame = Duration(milliseconds: 100);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    dismissedHints = (prefs.getStringList(_hintsKey) ?? const []).toSet();
    final rawProfile = prefs.getString(_profileKey);
    if (rawProfile != null) {
      try {
        profile =
            Profile.fromJson(jsonDecode(rawProfile) as Map<String, dynamic>);
      } catch (_) {
        profile = Profile(); // a corrupt profile must not brick the game
      }
    }
    final raw = prefs.getString(_saveKey);

    if (raw == null) {
      state = _freshRun();
    } else {
      try {
        state = GameState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        // THE PORT DOES NOT WORK WHILE YOU ARE NOT PLAYING.
        //
        // This used to run the sim forward for however long the app had been
        // closed. It was meant generously — no timer to skip, nothing to buy
        // to speed it up — but it made putting the phone down consequential in
        // a game whose entire premise is that it should not be. A run left
        // overnight came back to a port whose people had starved and whose
        // coin had gone to wages, and one of those aftermaths reached the
        // developer as a "run report" of 89 days of population zero.
        //
        // Freezing the world instead means the only thing that advances the
        // port is you, deciding to advance it. `catchUp` is kept because the
        // behaviour is still worth being able to reason about and is covered
        // by tests, but nothing in the app calls it.
        if (Balance.progressWhileAway) {
          final savedAt = prefs.getInt(_savedAtKey);
          if (savedAt != null) {
            final away = DateTime.now().millisecondsSinceEpoch - savedAt;
            if (away > 0) {
              lastCatchUpTicks = state.catchUp(
                Duration(milliseconds: away),
                ticksPerSecond: offlineTicksPerSecond,
              );
            }
          }
        }
      } catch (_) {
        // A corrupt or incompatible save should not brick the app.
        state = _freshRun();
      }
    }

    ready = true;
    _syncTimer();
    notifyListeners();
  }

  /// A brand new port under the charters currently in force.
  ///
  /// Every path that begins a run goes through here. It used to be three
  /// separate `GameState.newGame()` calls and only one of them passed the
  /// charters, so a run begun from the load fallback was quietly simulated at
  /// difficulty 0 while the charter screen still listed the hardships as in
  /// force — and the win was then filed on the "No hardship" ladder.
  GameState _freshRun() {
    profile.reconcile();
    return GameState.newGame(seed: _newSeed(), charters: profile.activeSet);
  }

  /// A fresh world number.
  ///
  /// `millisecondsSinceEpoch % 100000` was periodic with a hundred-second
  /// wall-clock cycle, so two runs begun a hundred seconds apart drew the same
  /// world. Microseconds across the full positive range do not repeat in any
  /// span a player will notice.
  int _newSeed() =>
      seedOverride ?? (DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF);

  /// The clock only exists while it has something to do. A paused or finished
  /// game holds no timer at all, which keeps a backgrounded port off the CPU.
  /// True while the app is not on screen.
  ///
  /// The timer kept running when the app went to the background, so the port
  /// went on working in a pocket. Saving on suspend was not enough on its own:
  /// it recorded the leaving, it did not stop the clock.
  bool _away = false;

  /// Called from the app's lifecycle observer. Stops the world on the way out
  /// and starts it again on the way back in, with no catching up in between —
  /// see [Balance.progressWhileAway].
  void setAway(bool away) {
    if (_away == away) return;
    _away = away;
    _syncTimer();
  }

  void _syncTimer() {
    if (!ready || speed == 0 || state.lighthouseBuilt || _away) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(_frame, (_) => _onFrame());
  }

  void _onFrame() {
    if (state.lighthouseBuilt) {
      _syncTimer();
      notifyListeners();
      return;
    }

    _accumulator += _frame.inMilliseconds / 1000.0 * baseTicksPerSecond * speed;
    var steps = 0;
    while (_accumulator >= 1.0 && steps < 64) {
      _accumulator -= 1.0;
      state.step();
      steps++;
    }
    if (steps > 0) {
      notifyListeners();
      _autosave();
    }
  }

  /// Write the run to storage, at most once every [_autosaveGap].
  ///
  /// THIS EXISTS BECAUSE NOTHING CALLED [save]. The method was written, was
  /// covered by a test that invoked it directly, and had no caller anywhere in
  /// the app — no lifecycle observer, no timer, no button. A run therefore
  /// lived only in memory: closing the tab, or Android reclaiming the process,
  /// silently threw away the whole port. The test passed the entire time,
  /// because it verified that saving works rather than that saving happens.
  ///
  /// The offline catch-up in [load] depends on this too: with no [_savedAtKey]
  /// ever written, "while you were away" could never have anything to resolve.
  void _autosave() {
    if (!ready) return;
    final now = DateTime.now();
    if (_lastSaveAt != null && now.difference(_lastSaveAt!) < _autosaveGap) {
      return;
    }
    _lastSaveAt = now;
    unawaited(save());
  }

  DateTime? _lastSaveAt;

  /// Often enough that a crash costs seconds, rarely enough that a phone is not
  /// writing storage every frame.
  static const Duration _autosaveGap = Duration(seconds: 10);

  /// Persist right now, whatever the gap. For app suspend and for the moments
  /// that must not be lost — a hire, a voyage, a finished lighthouse.
  Future<void> saveNow() {
    _lastSaveAt = DateTime.now();
    return save();
  }

  void setSpeed(double value) {
    speed = value;
    _syncTimer();
    notifyListeners();
  }

  void cycleSpeed() {
    final i = speeds.indexOf(speed);
    setSpeed(speeds[(i + 1) % speeds.length]);
  }

  /// Run the player's action, then repaint. Every mutation funnels through
  /// here so the UI can never drift from simulation state.
  void act(void Function(GameState s) action) {
    action(state);
    _syncTimer(); // finishing the lighthouse stops the clock
    notifyListeners();
    // A deliberate action is exactly what a player would be sick to lose.
    _autosave();
  }

  Future<void> save() async {
    if (!ready) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saveKey, jsonEncode(state.toJson()));
    await prefs.setInt(_savedAtKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  Future<void> dismissHint(String id) async {
    dismissedHints = {...dismissedHints, id};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hintsKey, dismissedHints.toList());
  }

  Future<void> saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  /// Record a finished run and offer three charters to choose between.
  ///
  /// Called once, the moment the light is lit. The offer is seeded from the
  /// run itself so closing the app cannot reroll it — the choice is meant to
  /// be a decision, not a slot machine.
  ///
  /// The record is written before anything can go wrong with the offer. It used
  /// to return early when an older choice was still unresolved, which threw the
  /// finished run away entirely — you sailed a hundred and twenty days and the
  /// ladder never heard about it. A run that is finished is finished; the offer
  /// is a separate question.
  Future<void> recordVictory() async {
    if (state.victoryRecorded) return; // this run has already been filed
    state.victoryRecorded = true;

    profile.runs.add(RunRecord(
      days: state.day,
      difficulty: state.charters.difficulty,
      population: state.population,
      charterIds: state.charters.ids,
    ));

    // Only offer if nothing is outstanding, and never overwrite an offer the
    // player has not answered yet.
    if (!profile.hasChoicePending) {
      profile.pendingChoice = profile.offer(state.rng.seed ^ state.day);
    }
    notifyListeners();
    await saveProfile();
    await saveNow();
  }

  /// Take one of the offered charters into the collection.
  ///
  /// An empty id means "no charter" — the all-owned case — and must not be
  /// written into the collection, or the profile accumulates a charter with no
  /// name that [charterById] can never resolve.
  Future<void> chooseCharter(String id) async {
    profile.pendingChoice = const [];
    if (id.isNotEmpty) profile.owned.add(id);
    notifyListeners();
    await saveProfile();
  }

  /// Toggle a charter for the next run, refusing anything unaffordable.
  void toggleCharter(String id) {
    if (profile.active.contains(id)) {
      profile.active.remove(id);
    } else {
      profile.active.add(id);
      if (!profile.activeSet.isLegal) profile.active.remove(id);
    }
    notifyListeners();
    saveProfile();
  }

  /// Begin a fresh run under the charters currently in force. The profile
  /// itself is untouched — that is the whole point of keeping it separate.
  Future<void> startNewRun() async {
    state = _freshRun();
    lastCatchUpTicks = 0;
    speed = 1;
    _syncTimer();
    notifyListeners();
    await saveProfile();
    // Write the new port immediately rather than deleting the old save and
    // leaving nothing behind until the next autosave.
    await saveNow();
  }

  Future<void> resetGame() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hintsKey);
    dismissedHints = {};
    state = _freshRun();
    lastCatchUpTicks = 0;
    speed = 1;
    _syncTimer();
    notifyListeners();
    await saveNow();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
