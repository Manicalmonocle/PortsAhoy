/// The island the port is built on.
///
/// Generated from a pure function of tile coordinates, so it is identical on
/// every device and in every save with nothing to serialise. Pure Dart, like
/// the rest of `lib/sim/`.
library;

import 'dart:math' as math;

enum Tile { water, sand, grass, trees, rock }

class Terrain {
  /// The island is a [size] × [size] grid of tiles.
  ///
  /// 26, UP FROM 20, because a full port no longer fit. Every shed is two
  /// tiles square and the old island held 31 of them before auto-placement ran
  /// out of room; played runs end on 22 to 28 buildings, houses included, and
  /// the livestock update added four more kinds. Past the ceiling a shed was
  /// built, worked, and simply never drawn — "after so many buildings they
  /// stop showing up on the island".
  static const int size = 26;

  /// The size every save was written at before the island grew. A save that
  /// does not say otherwise is on this grid; see [legacyShift].
  static const int legacySize = 20;

  /// How far a building on the old grid moves to stand on the same ground on
  /// this one. The old island sits inside the new one, centred, so this is
  /// the same in both directions.
  static int legacyShift(int savedSize) => (size - savedSize) ~/ 2;

  static double _hash(int n) {
    final x = math.sin(n * 12.9898 + 4.1414) * 43758.5453;
    return x - x.floorToDouble();
  }

  static Tile at(int col, int row) {
    if (col < 0 || row < 0 || col >= size || row >= size) return Tile.water;

    const centre = (size - 1) / 2.0;
    final dx = col - centre;
    final dy = row - centre;
    final d = math.sqrt(dx * dx + dy * dy);

    // A wobbly coastline reads as land rather than as a drawn circle.
    final angle = math.atan2(dy, dx);
    // The old coastline scaled up by the same factor at every angle, so the
    // island is the same shape, larger, and contains the old one entirely.
    // Kept clear of the grid edge so it always sits in open water.
    const grow = 1.218;
    final radius = grow *
        (7.8 + math.sin(angle * 3) * 0.85 + math.sin(angle * 5 + 1.4) * 0.55);

    if (d > radius) return Tile.water;
    if (d > radius - 1.15) return Tile.sand;

    // Keyed to the OLD grid's coordinates, so the old island's trees and rocks
    // are exactly where they were, relative to the coast — a save from before
    // the island grew finds the same ground under every shed.
    const o = (size - legacySize) ~/ 2;
    final h = _hash((col - o) * 131 + (row - o) * 17);
    if (h > 0.935) return Tile.trees;
    if (h > 0.905) return Tile.rock;
    return Tile.grass;
  }

  /// Trees and rock are scenery you must build around.
  static bool isBuildable(Tile t) => t == Tile.grass || t == Tile.sand;

  static bool buildableAt(int col, int row) => isBuildable(at(col, row));

  /// Sand tiles that touch water — where a quay makes sense.
  static bool isShore(int col, int row) {
    if (at(col, row) != Tile.sand) return false;
    for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      if (at(col + d[0], row + d[1]) == Tile.water) return true;
    }
    return false;
  }

  static int get buildableTileCount {
    var n = 0;
    for (var c = 0; c < size; c++) {
      for (var r = 0; r < size; r++) {
        if (buildableAt(c, r)) n++;
      }
    }
    return n;
  }
}
