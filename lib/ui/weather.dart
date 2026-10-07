/// The port's wind and weather at a moment: one reading, shared by everything
/// that has to agree about it.
///
/// It began inside the world painter, which was the only thing that needed
/// it. Sound needs exactly the same numbers — a gale has to SOUND like the gale
/// on screen, rain has to start when the rain does — and two copies of the
/// rules would drift the first time either was tuned. So it lives here, and
/// both read it.
library;

import 'dart:math' as math;

import '../sim/events.dart';
import '../sim/game_state.dart';

class Weather {
  const Weather._({
    required this.windX,
    required this.windZ,
    required this.wind,
    required this.storm,
    required this.frost,
    required this.ice,
    required this.fair,
    required this.rot,
    required this.seen,
  });

  /// Where the wind is blowing TO, on the ground plane, and how hard (0-1).
  /// One wind for the whole port: smoke leans with it, windmills turn with
  /// it, pennants snap with it, the sea roughens under it, and it is the
  /// wind you hear.
  final double windX, windZ, wind;

  /// How much of each kind of weather there is, 0 to 1. Each builds through
  /// its event's omen and eases out at the end.
  final double storm, frost, ice, fair, rot;

  /// Events that put something in the world rather than change its light —
  /// a fire, sails offshore, a wreck — with how far into being each is.
  final List<(ActiveEvent, double)> seen;

  /// How present an event is at [now], 0 to 1.
  ///
  /// THE OMEN IS THE POINT. Every event is drawn some ticks before it starts,
  /// and for most of the game's life that warning lived only in the log.
  /// Weather now builds through its omen — smoke beginning to lean, frost
  /// whitening the grass, ice making in the shallows — to two thirds of its
  /// strength, so the real thing is still a step up when it lands. It eases
  /// out over its last hours rather than switching off.
  static double presence(ActiveEvent e, int now) {
    if (e.isOmen(now)) {
      final span = math.max(1, e.startTick - e.omenTick);
      return (1 - (e.startTick - now) / span).clamp(0.0, 1.0) * 0.66;
    }
    if (e.isActive(now)) {
      const ease = 12; // ticks to ease in and out
      final inK = ((now - e.startTick + 1) / ease).clamp(0.0, 1.0);
      final outK = ((e.endTick - now) / ease).clamp(0.0, 1.0);
      return math.min(inK, outK);
    }
    return 0;
  }

  /// The weather over [state] at [seconds] of animation time. The seconds
  /// only move the everyday breeze, which veers slowly so smoke never leans
  /// quite the same way twice; events are read from the sim.
  factory Weather.of(GameState state, double seconds) {
    final now = state.tick;
    var dir = 0.35 + math.sin(seconds * 0.021) * 0.35;
    var strength = 0.32 + math.sin(seconds * 0.047 + 1.3) * 0.08;

    void pull(double toDir, double toStrength, double k) {
      // The short way round, so a veer never spins the long way.
      var d = toDir - dir;
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        d += 2 * math.pi;
      }
      dir += d * k;
      strength += (toStrength - strength) * k;
    }

    var storm = 0.0, frost = 0.0, ice = 0.0, fair = 0.0, rot = 0.0;
    final seen = <(ActiveEvent, double)>[];
    for (final e in state.events.active) {
      final k = presence(e, now);
      if (k <= 0) continue;
      switch (e.defId) {
        // A gale out of the north-east: everything lies over the other way,
        // the light goes, and it rains.
        case 'north_easterly':
          pull(math.pi * 1.25, 1.0, k);
          storm = math.max(storm, k);
        case 'fair_winds':
          pull(dir, 0.62, k);
          fair = math.max(fair, k);
        // Cold air is still air. Smoke stands straight up in a frost.
        case 'cold_snap':
          pull(dir, 0.08, k);
          frost = math.max(frost, k);
        case 'the_sound_froze':
          pull(dir, 0.05, k);
          ice = math.max(ice, k);
          frost = math.max(frost, k * 0.8);
        case 'retting_rot':
          rot = math.max(rot, k);
        case 'shed_fire' ||
              'privateer_scare' ||
              'southern_convoy' ||
              'wreck_on_the_skerries':
          seen.add((e, k));
      }
    }
    return Weather._(
      windX: math.cos(dir),
      windZ: math.sin(dir),
      wind: strength.clamp(0.0, 1.0),
      storm: storm,
      frost: frost,
      ice: ice,
      fair: fair,
      rot: rot,
      seen: seen,
    );
  }
}
