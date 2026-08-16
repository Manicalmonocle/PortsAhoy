// Renders Play-Store screenshots from the real game, at the phone resolution
// Google wants (1080x1920). Regenerate with:
//     flutter test test/screenshots_test.dart --update-goldens
// then collect them from test/goldens/store/.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/game_controller.dart';
import 'package:ports_ahoy/main.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GameController> boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3.0; // 360x640 logical, a real phone shape
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final c = GameController();
  await c.load();
  c.setSpeed(0);
  addTearDown(c.dispose);
  return c;
}

/// A believable mid-game port, so the shots show a real place.
void grow(GameState g) {
  g.coin = 6400;
  for (final id in [
    'sawmill', 'flax_field', 'ropewalk', 'weaver', 'mine', 'smithy',
    'warehouse', 'house', 'house', 'farm', 'forest_camp', 'cooperage',
    'import_berth', 'warehouse',
  ]) {
    g.unlocked.add(id);
    for (final r in Resource.values) {
      g.stock[r] = 260;
    }
    g.build(defById(id));
  }
  g.population = 34;
  for (var i = 0; i < g.buildings.length; i++) {
    if (i % 5 != 4) g.setWorkers(i, g.buildings[i].def.maxWorkers);
  }
  g.coin = 4820;
  for (var i = 0; i < 90; i++) {
    g.step();
  }
}

void main() {
  Future<void> shot(WidgetTester tester, GameController c, String name) async {
    await tester.pumpWidget(PortsAhoyApp(controller: c));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(PortsAhoyApp), matchesGoldenFile('store/$name.png'));
  }

  testWidgets('1 — the harbour', (tester) async {
    final c = await boot(tester);
    grow(c.state);
    await shot(tester, c, '01-harbour');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('2 — the quay', (tester) async {
    final c = await boot(tester);
    grow(c.state);
    await tester.pumpWidget(PortsAhoyApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quay'));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(PortsAhoyApp), matchesGoldenFile('store/02-quay.png'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('3 — trade', (tester) async {
    final c = await boot(tester);
    grow(c.state);
    await tester.pumpWidget(PortsAhoyApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trade'));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(PortsAhoyApp), matchesGoldenFile('store/03-trade.png'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('4 — the sheds', (tester) async {
    final c = await boot(tester);
    grow(c.state);
    await tester.pumpWidget(PortsAhoyApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sheds'));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(PortsAhoyApp), matchesGoldenFile('store/04-sheds.png'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('5 — build', (tester) async {
    final c = await boot(tester);
    grow(c.state);
    await tester.pumpWidget(PortsAhoyApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build'));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(PortsAhoyApp), matchesGoldenFile('store/05-build.png'));
    await tester.pumpWidget(const SizedBox());
  });
}
