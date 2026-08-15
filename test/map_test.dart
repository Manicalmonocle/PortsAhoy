import 'dart:convert';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/game_controller.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/terrain.dart';
import 'package:ports_ahoy/ui/world_view.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:ports_ahoy/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('terrain', () {
    test('the island has water all round its edge', () {
      for (var i = 0; i < Terrain.size; i++) {
        expect(Terrain.at(0, i), Tile.water);
        expect(Terrain.at(Terrain.size - 1, i), Tile.water);
        expect(Terrain.at(i, 0), Tile.water);
        expect(Terrain.at(i, Terrain.size - 1), Tile.water);
      }
    });

    test('there is plenty of ground to build on', () {
      expect(Terrain.buildableTileCount, greaterThan(120));
    });

    test('generation is pure and stable', () {
      for (var c = 0; c < Terrain.size; c++) {
        for (var r = 0; r < Terrain.size; r++) {
          expect(Terrain.at(c, r), Terrain.at(c, r));
        }
      }
    });

    test('out of bounds is water, never a crash', () {
      expect(Terrain.at(-5, 3), Tile.water);
      expect(Terrain.at(3, 999), Tile.water);
    });
  });

  group('placement', () {
    test('a new game lays every building on the map', () {
      final g = GameState.newGame();
      for (final b in g.buildings) {
        expect(b.isPlaced, isTrue, reason: b.defId);
      }
    });

    test('no two buildings overlap', () {
      final g = GameState.newGame();
      for (final def in kBuildingDefs) {
        g.coin = 100000;
        g.unlocked.add(def.id); // placement, not progression, is under test
        for (final r in def.cost.keys) {
          g.stock[r] = 1000;
        }
        expect(g.build(def), isTrue);
      }

      final claimed = <String>{};
      for (final b in g.buildings) {
        final f = b.def.footprint;
        for (var c = b.col; c < b.col + f; c++) {
          for (var r = b.row; r < b.row + f; r++) {
            expect(claimed.add('$c,$r'), isTrue,
                reason: '${b.defId} overlaps at $c,$r');
          }
        }
      }
    });

    test('every building stands on buildable ground', () {
      final g = GameState.newGame();
      for (final b in g.buildings) {
        final f = b.def.footprint;
        for (var c = b.col; c < b.col + f; c++) {
          for (var r = b.row; r < b.row + f; r++) {
            expect(Terrain.buildableAt(c, r), isTrue, reason: b.defId);
          }
        }
      }
    });

    test('a building can be moved to free ground', () {
      final g = GameState.newGame();
      final b = g.buildings.first;

      // Find somewhere legitimately free.
      int? tc, tr;
      for (var c = 0; c < Terrain.size && tc == null; c++) {
        for (var r = 0; r < Terrain.size; r++) {
          if (c == b.col && r == b.row) continue;
          if (g.canPlaceAt(b.def, c, r, ignore: b)) {
            tc = c;
            tr = r;
            break;
          }
        }
      }
      expect(tc, isNotNull);

      expect(g.moveBuilding(b, tc!, tr!), isTrue);
      expect(b.col, tc);
      expect(b.row, tr);
    });

    test('a building cannot be moved onto another', () {
      final g = GameState.newGame();
      final a = g.buildings[0];
      final other = g.buildings[1];
      final was = [a.col, a.row];

      expect(g.moveBuilding(a, other.col, other.row), isFalse);
      expect([a.col, a.row], was, reason: 'a refused move must change nothing');
    });

    test('a building cannot be moved into the sea or onto trees', () {
      final g = GameState.newGame();
      final b = g.buildings.first;
      expect(g.moveBuilding(b, 0, 0), isFalse); // water at the corner

      // Find a tree tile and try to build on it.
      for (var c = 0; c < Terrain.size; c++) {
        for (var r = 0; r < Terrain.size; r++) {
          if (Terrain.at(c, r) == Tile.trees) {
            expect(g.canPlaceAt(b.def, c, r, ignore: b), isFalse);
            return;
          }
        }
      }
    });

    test('a building can be moved back onto its own tiles', () {
      final g = GameState.newGame();
      final b = g.buildings.first;
      expect(g.moveBuilding(b, b.col, b.row), isTrue);
    });

    test('buildingAt finds every tile of a footprint', () {
      final g = GameState.newGame();
      final b = g.buildings.first;
      for (var c = b.col; c < b.col + b.def.footprint; c++) {
        for (var r = b.row; r < b.row + b.def.footprint; r++) {
          expect(identical(g.buildingAt(c, r), b), isTrue);
        }
      }
    });

    test('positions round-trip through a save', () {
      final g = GameState.newGame();
      final before = g.buildings.map((b) => '${b.col},${b.row}').toList();
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(restored.buildings.map((b) => '${b.col},${b.row}').toList(),
          before);
    });

    test('a save from before the map existed lays itself out on load', () {
      final g = GameState.newGame();
      final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
      for (final b in json['buildings'] as List) {
        (b as Map<String, dynamic>).remove('col');
        b.remove('row');
      }
      final restored = GameState.fromJson(json);
      for (final b in restored.buildings) {
        expect(b.isPlaced, isTrue);
      }
    });
  });

  group('3D camera', () {
    test('the eye sits the right distance from what it looks at', () {
      final cam = Camera3D(target: Vector3.zero(), distance: 26);
      expect((cam.eye - cam.target).length, closeTo(26, 1e-6));
    });

    test('orbiting moves the eye but never the target', () {
      final cam = Camera3D(target: Vector3(1, 0, 2), distance: 20);
      final before = cam.eye.clone();
      cam.yaw += 1.0;
      expect(cam.eye.x, isNot(closeTo(before.x, 1e-3)));
      expect(cam.target, Vector3(1, 0, 2));
      expect((cam.eye - cam.target).length, closeTo(20, 1e-6));
    });

    test('tilting up raises the eye', () {
      final cam = Camera3D(target: Vector3.zero(), pitch: 0.6);
      final low = cam.eye.y;
      cam.pitch = 1.2;
      expect(cam.eye.y, greaterThan(low));
    });

    test('a point on the ground projects, and unprojects back to itself', () {
      const size = Size(400, 700);
      final cam = Camera3D(target: Vector3.zero());
      final proj = Projector(cam, size);

      for (final p in [
        Vector3.zero(),
        Vector3(3, 0, -2),
        Vector3(-4, 0, 5),
      ]) {
        final screen = proj.project(p);
        expect(screen.visible, isTrue);
        final back = proj.toGround(screen.screen, groundY: 0);
        expect(back, isNotNull);
        expect(back!.x, closeTo(p.x, 1e-3), reason: 'x round-trip');
        expect(back.z, closeTo(p.z, 1e-3), reason: 'z round-trip');
      }
    });

    test('perspective makes nearer things bigger', () {
      const size = Size(400, 700);
      final cam = Camera3D(target: Vector3.zero(), yaw: -math.pi / 2);
      final proj = Projector(cam, size);

      // At this yaw the eye sits at negative z, so z = -6 is the near segment.
      expect(cam.eye.z, lessThan(0));

      double widthAt(double z) {
        final a = proj.project(Vector3(-1, 0, z));
        final b = proj.project(Vector3(1, 0, z));
        return (b.screen.dx - a.screen.dx).abs();
      }

      expect(widthAt(-6), greaterThan(widthAt(6)),
          reason: 'this is the whole difference from an isometric projection');
    });

    test('the horizon is behind the camera, so nothing projects from behind',
        () {
      const size = Size(400, 700);
      final cam = Camera3D(target: Vector3.zero(), distance: 20);
      final proj = Projector(cam, size);
      final behind = proj.project(cam.eye + (cam.eye - cam.target));
      expect(behind.visible, isFalse);
    });
  });

  group('rendering', () {
    testWidgets('paints a working port', (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final controller = GameController();
      await controller.load();
      controller.setSpeed(0);
      addTearDown(controller.dispose);

      final g = controller.state;
      g.coin = 100000;
      for (final id in [
        'sawmill', 'flax_field', 'ropewalk', 'weaver', 'mine',
        'smithy', 'warehouse', 'house', 'import_berth', 'distillery',
      ]) {
        g.unlocked.add(id);
        for (final r in defById(id).cost.keys) {
          g.stock[r] = 1000;
        }
        g.build(defById(id));
      }
      g.population = 60;
      for (var i = 0; i < g.buildings.length; i++) {
        if (i % 4 != 3) g.setWorkers(i, g.buildings[i].def.maxWorkers);
      }
      for (var i = 0; i < 30; i++) {
        g.step();
      }

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          backgroundColor: Palette.deep,
          body: WorldView(controller: controller, onInspect: (_) {}),
        ),
      ));
      await tester.pump();

      await expectLater(
          find.byType(WorldView), matchesGoldenFile('goldens/iso_map.png'));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
