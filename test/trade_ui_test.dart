import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/game_controller.dart';
import 'package:ports_ahoy/main.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GameController> pumpGame(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final c = GameController();
  await c.load();
  c.setSpeed(0);
  addTearDown(c.dispose);

  await tester.pumpWidget(PortsAhoyApp(controller: c));
  await tester.pump();
  return c;
}

void main() {
  testWidgets('sending a consignment takes the cargo out of the stores',
      (tester) async {
    final c = await pumpGame(tester);
    c.act((s) {
      s.stock[Resource.timber] = 150;
      s.coin = 5000;
    });
    final before = c.state.stock[Resource.timber];

    await tester.tap(find.text('Trade'));
    await tester.pumpAndSettle();

    // Scroll the panel until the timber cargo row is actually built, then
    // anchor on it. The rows sit well below the fold.
    await tester.dragUntilVisible(
      find.text('Timber'),
      find.byType(ListView).last,
      const Offset(0, -140),
      maxIteration: 60,
    );
    await tester.pumpAndSettle();

    final row = find
        .ancestor(of: find.text('Timber'), matching: find.byType(Card))
        .first;
    final plus = find.descendant(
        of: row, matching: find.byIcon(Icons.add_circle_outline));
    await tester.tap(plus.first);
    await tester.pumpAndSettle();
    expect(c.state.stock[Resource.timber], before,
        reason: 'loading the hold must not touch the stores yet');

    // Now send it.
    final send = find.text('Send');
    await tester.dragUntilVisible(
      send,
      find.byType(ListView).last,
      const Offset(0, -120),
      maxIteration: 40,
    );
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(c.state.voyages, hasLength(1), reason: 'the voyage should exist');
    expect(c.state.stock[Resource.timber], lessThan(before),
        reason: 'the cargo should have left the stores');
    expect(c.state.stock[Resource.timber],
        before - c.state.voyages.first.totalCargo,
        reason: 'exactly the loaded amount, no more and no less');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  // Reported from play: "can we add visibility when merchants are helping or
  // captains are used. like a markup % then + another % for the merchant or x
  // days of sailing - % for speed of sailing". The retinue's whole effect was
  // invisible at the point of decision — the panel showed one total and never
  // said who had moved it.
  testWidgets('the quote says who moved it, and fits a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final c = GameController(seedOverride: 20260815);
    await c.load();
    c.setSpeed(0);
    addTearDown(c.dispose);
    await tester.pumpWidget(PortsAhoyApp(controller: c));

    c.act((s) {
      s.stock[Resource.timber] = 150;
      s.coin = 5000;
      s.captainLevel = 1;
      s.merchantLevel = 1;
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trade'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('Timber'),
        find.byType(ListView).last, const Offset(0, -140), maxIteration: 60);
    await tester.pumpAndSettle();
    final row = find
        .ancestor(of: find.text('Timber'), matching: find.byType(Card))
        .first;
    await tester.tap(find
        .descendant(of: row, matching: find.byIcon(Icons.add_circle_outline))
        .first);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('You receive'),
        find.byType(ListView).last, const Offset(0, -120), maxIteration: 60);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the itemised quote must fit a 360x640 handset');

    // The merchant's contribution and their cut are both named.
    expect(find.textContaining('Bettine Cray'), findsWidgets,
        reason: 'the player should see which of their people earned this');
    expect(find.textContaining('commission'), findsWidgets,
        reason: 'and what that person took back');

    // And the captain's effect on the crossing.
    expect(find.textContaining('Maren Holt'), findsWidgets);
    expect(find.textContaining('% faster'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
