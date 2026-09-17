// A dev harness, not a golden: renders one of every building with no UI over
// it and writes the PNG somewhere you can look at it. The world painter is
// procedural geometry, and there is no way to judge a silhouette except by
// seeing it — so this is the feedback loop for any visual work.
//
//   flutter test test/visual_probe_test.dart
//   -> writes /tmp/claude-1000/.../scratchpad/world.png (or VISUAL_OUT)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/game_controller.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/market.dart';
import 'package:ports_ahoy/sim/terrain.dart';
import 'package:ports_ahoy/ui/world_view.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  testWidgets('render one of every shed', (tester) async {
    final out = Platform.environment['VISUAL_OUT'] ??
        '/tmp/claude-1000/-home-kevin/2ca3c03f-7cd7-4476-a799-87ec86cbddd5/scratchpad/world.png';

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final c = GameController(seedOverride: 20260815);
    await c.load();
    c.setSpeed(0);
    addTearDown(c.dispose);
    final g = c.state;

    // Every building, placed on a grid across the island so each is visible.
    // Placement bypasses cost: this is a lineup, not a run.
    g.buildings.clear();
    // Collect every clear buildable 2x2 spot once, then drop the buildings
    // onto them. No search-with-wraparound, which could loop forever the
    // moment it walked off the island.
    bool clear(int c, int r) {
      for (var dc = 0; dc < 2; dc++) {
        for (var dr = 0; dr < 2; dr++) {
          if (!Terrain.buildableAt(c + dc, r + dr)) return false;
        }
      }
      return true;
    }
    final spots = <List<int>>[];
    for (var r = 2; r < Terrain.size - 2 && spots.length < 40; r += 3) {
      for (var c = 2; c < Terrain.size - 2 && spots.length < 40; c += 3) {
        if (clear(c, r)) spots.add([c, r]);
      }
    }
    for (var i = 0; i < kBuildingDefs.length && i < spots.length; i++) {
      final def = kBuildingDefs[i];
      g.buildings.add(Building(defId: def.id)
        ..col = spots[i][0]
        ..row = spots[i][1]
        ..workers = def.maxWorkers > 0 ? (i % 3 == 2 ? 0 : def.maxWorkers) : 0);
    }
    // A few ships at the quay so the moored hulls render.
    g.market.ships.add(Ship(name: 'Test Crown', departTick: 99999,
        offers: const [], foreign: false));
    g.market.ships.add(Ship(name: 'Test Free', departTick: 99999,
        offers: const [], foreign: true));
    g.market.ships.add(Ship(name: 'Test Crown 2', departTick: 99999,
        offers: const [], foreign: false));
    // Ripen the grange so its fields show green in the lineup.
    // Grown, so ripening sheds draw at full size rather than as the stub a
    // freshly raised one would be.
    for (final b in g.buildings) {
      if (b.def.ripens) b.maturity = 1.0;
    }
    g.population = 80;
    g.tick = 240; // mid-morning, so anything tick-driven is mid-motion

    // Aim at the first moored ship, for judging boat geometry.
    List<double>? shipSpot;
    if (Platform.environment['VISUAL_SHIP'] != null) {
      outer:
      for (var col = 0; col < Terrain.size; col++) {
        for (var row = 0; row < Terrain.size; row++) {
          if (!Terrain.isShore(col, row)) continue;
          for (final d in const [[1,0],[-1,0],[0,1],[0,-1]]) {
            if (Terrain.at(col + d[0], row + d[1]) == Tile.water) {
              final c = tileCorner(col + 0.5 + d[0], row + 0.5 + d[1], 0);
              shipSpot = [c.x, c.z];
              break outer;
            }
          }
        }
      }
    }

    // Close in on the middle of the lineup, or nothing is big enough to judge.
    final zoom = Platform.environment['VISUAL_ZOOM'];
    final cam = shipSpot != null
        ? (Camera3D(
            target: Vector3(shipSpot[0], 0, shipSpot[1]),
            distance: 5, pitch: 0.6))
        : zoom == null
        ? null
        : Camera3D(
            target: tileCorner(
                double.parse(Platform.environment['VISUAL_COL'] ?? '9'),
                double.parse(Platform.environment['VISUAL_ROW'] ?? '7'), 0),
            distance: double.parse(zoom),
            pitch: 0.7,
          );

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: WorldView(
          controller: c,
          onInspect: (_) {},
          fullBleed: true,
          initialCamera: cam,
        ),
      ),
    ));
    File('/tmp/claude-1000/-home-kevin/2ca3c03f-7cd7-4476-a799-87ec86cbddd5/scratchpad/trace.txt').writeAsStringSync('PUMPED\n', mode: FileMode.append);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    File('/tmp/claude-1000/-home-kevin/2ca3c03f-7cd7-4476-a799-87ec86cbddd5/scratchpad/trace.txt').writeAsStringSync('RENDERED\n', mode: FileMode.append);

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(File(out).existsSync(), isTrue);
  });
}
