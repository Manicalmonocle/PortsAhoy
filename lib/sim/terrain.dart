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
  static const int size = 20;

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
    // Kept clear of the grid edge so the island always sits in open water.
    final radius = 7.8 +
        math.sin(angle * 3) * 0.85 +
        math.sin(angle * 5 + 1.4) * 0.55;

    if (d > radius) return Tile.water;
    if (d > radius - 1.15) return Tile.sand;

    final h = _hash(col * 131 + row * 17);
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
