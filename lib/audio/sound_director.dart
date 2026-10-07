/// What the port sounds like, decided from what the port is doing.
///
/// Nothing in the sim knows sound exists. The director watches the game the
/// way a player does — a shed going up, a hull coming in, a cutter alongside —
/// and plays what that moment sounds like. Most of it is read by comparing
/// the port with how it looked a moment ago, rather than from the journal:
/// the journal stops recording at 300 marks, and a long run would go quiet
/// partway through.
///
/// Trade at the quay is the exception. A sale is one tap by the player and
/// the market tab plays the coins itself, at the moment of the tap.
library;

import 'dart:async';
import 'dart:math' as math;

import '../game_controller.dart';
import '../sim/game_state.dart';
import '../ui/weather.dart';
import 'sound_board.dart';

class SoundDirector {
  SoundDirector(this.controller, {SoundBoard? board, math.Random? random})
      : board = board ?? SoundBoard.instance,
        _random = random ?? math.Random() {
    _snapshot(controller.state);
    controller.addListener(_onChange);
    // Ambience is set on its own steady beat rather than on every game tick,
    // because the sea keeps breathing while the port is paused.
    _ambience = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
  }

  final GameController controller;
  final SoundBoard board;
  final math.Random _random;
  Timer? _ambience;

  // How the port looked last time.
  GameState? _state;
  int _placed = 0;
  int _voyages = 0;
  int _ships = 0;
  int _marks = 0;
  bool _cutter = false;
  bool _lit = false;
  final Set<String> _live = {};

  // The ambient beat.
  double _seconds = 0;
  double _nextGull = 20;
  double _nextThunder = 6;
  final Map<Bed, double> _level = {for (final b in Bed.values) b: 0};

  void dispose() {
    _ambience?.cancel();
    controller.removeListener(_onChange);
  }

  void _snapshot(GameState s) {
    _state = s;
    _placed = s.buildings.where((b) => b.isPlaced).length;
    _voyages = s.voyages.length;
    _ships = s.market.ships.length;
    _marks = s.journal.marks.length;
    _cutter = s.cutterOnStation;
    _lit = s.lighthouseBuilt;
    _live
      ..clear()
      ..addAll(s.events.live(s.tick).map((e) => e.defId));
  }

  void _onChange() {
    final s = controller.state;
    // A new run, or a load: take the port as it stands and play nothing for
    // it. Otherwise loading a port with forty sheds would hammer forty times.
    if (!identical(s, _state) || s.journal.marks.length < _marks) {
      _snapshot(s);
      return;
    }

    final placed = s.buildings.where((b) => b.isPlaced).length;
    if (placed > _placed) board.play(Sfx.hammer);

    if (s.voyages.length < _voyages) {
      // Home, and paid: a bell to say she is in, coins for the cargo.
      board.play(Sfx.bell);
      board.play(Sfx.coins, volume: 0.9);
    } else if (s.voyages.length > _voyages) {
      // Casting off: the same bell, further away.
      board.play(Sfx.bell, volume: 0.55);
    }

    // A trader standing in. Quieter than your own hulls.
    if (s.market.ships.length > _ships) board.play(Sfx.bell, volume: 0.4);

    for (final m in s.journal.marks.skip(_marks)) {
      final code = m.code;
      if (code == null || code.isEmpty) continue;
      switch (code[0]) {
        case 'p':
          board.play(Sfx.cannon);
        case 'T':
          board.play(Sfx.coins);
      }
    }

    if (s.cutterOnStation && !_cutter) board.play(Sfx.alarm);
    if (s.lighthouseBuilt && !_lit) board.play(Sfx.chime);

    for (final e in s.events.live(s.tick)) {
      if (_live.contains(e.defId)) continue;
      switch (e.defId) {
        case 'north_easterly':
          board.play(Sfx.thunder);
        case 'shed_fire':
          board.play(Sfx.alarm);
      }
    }

    _snapshot(s);
  }

  /// One beat of ambience: the loops' levels, and the odd gull or thunderclap.
  /// Public so a test can step it without waiting on a timer.
  void tick([double dt = 0.25]) {
    _seconds += dt;
    final w = Weather.of(controller.state, _seconds);

    // The sea always, quietening under ice — a frozen sound is a still one.
    // The wind barely there on a calm day and roaring in a gale. Rain only in
    // a storm.
    final target = {
      Bed.sea: (0.5 + 0.25 * w.storm) * (1 - 0.8 * w.ice),
      Bed.wind: 0.06 + 0.6 * math.pow(w.wind, 1.6),
      Bed.rain: 0.65 * w.storm,
    };
    // Eased, so a gale arriving rises over seconds instead of switching on.
    final out = <Bed, double>{};
    for (final e in target.entries) {
      final now = _level[e.key]!;
      final next = now + (e.value - now) * 0.12;
      _level[e.key] = next;
      out[e.key] = next.clamp(0.0, 1.0);
    }
    board.setBeds(out);

    if (_seconds >= _nextGull) {
      _nextGull = _seconds + 18 + _random.nextDouble() * 34;
      // No gulls in a gale or over ice: they have the sense to be elsewhere.
      if (w.storm < 0.3 && w.ice < 0.5) {
        board.play(Sfx.gull, volume: 0.6 + _random.nextDouble() * 0.4);
      }
    }
    if (w.storm > 0.5 && _seconds >= _nextThunder) {
      _nextThunder = _seconds + 7 + _random.nextDouble() * 12;
      board.play(Sfx.thunder, volume: 0.5 + 0.5 * w.storm);
    }
  }
}
