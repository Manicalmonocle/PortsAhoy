import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim/game_state.dart';

/// Drives the simulation clock and owns persistence.
///
/// Speed is a free control, including the fastest setting. In a game funded by
/// timers this is the thing you would sell; here it is a button, and the
/// difficulty lives in allocation instead of waiting.
class GameController extends ChangeNotifier {
  GameController();

  static const String _saveKey = 'ports_ahoy_save_v1';
  static const String _savedAtKey = 'ports_ahoy_saved_at_ms';
  static const String _hintsKey = 'ports_ahoy_dismissed_hints';

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

  Timer? _timer;
  double _accumulator = 0;
  static const Duration _frame = Duration(milliseconds: 100);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    dismissedHints = (prefs.getStringList(_hintsKey) ?? const []).toSet();
    final raw = prefs.getString(_saveKey);

    if (raw == null) {
      state = GameState.newGame();
    } else {
      try {
        state = GameState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
      } catch (_) {
        // A corrupt or incompatible save should not brick the app.
        state = GameState.newGame();
      }
    }

    ready = true;
    _syncTimer();
    notifyListeners();
  }

  /// The clock only exists while it has something to do. A paused or finished
  /// game holds no timer at all, which keeps a backgrounded port off the CPU.
  void _syncTimer() {
    if (!ready || speed == 0 || state.lighthouseBuilt) {
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
    if (steps > 0) notifyListeners();
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
  }

  Future<void> save() async {
    if (!ready) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saveKey, jsonEncode(state.toJson()));
    await prefs.setInt(_savedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> dismissHint(String id) async {
    dismissedHints = {...dismissedHints, id};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hintsKey, dismissedHints.toList());
  }

  Future<void> resetGame() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_saveKey);
    await prefs.remove(_savedAtKey);
    await prefs.remove(_hintsKey);
    dismissedHints = {};
    state = GameState.newGame(seed: DateTime.now().millisecondsSinceEpoch % 100000);
    lastCatchUpTicks = 0;
    speed = 1;
    _syncTimer();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
