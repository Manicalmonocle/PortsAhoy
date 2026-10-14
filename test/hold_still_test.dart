// Screens that stay where you left them.
//
// Reported from play: "screens jump around at every tick making buying /
// selling aggravating", then "even scrolling through sheds and build menu
// jumps around". Every panel is rebuilt from the game's state on every tick,
// and any line that came or went moved everything below it. These tests hold
// the measurements that found each cause: a ship sailing from the top of the
// Quay, an offer filling, a ship's name wrapping as its "sails in" pill turned
// bold, every yard on the Sheds panel emptying at once, and the mood line
// crossing 30%.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/game_controller.dart';
import 'package:ports_ahoy/main.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/market.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:ports_ahoy/ui/hold_still.dart';
import 'package:ports_ahoy/ui/market_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A struggling working port, so stock and coin hover around the thresholds
/// that make lines come and go — the case a comfortable port never shows.
Future<GameController> struggling() async {
  SharedPreferences.setMockInitialValues({});
  final c = GameController(seedOverride: 20260815);
  await c.load();
  c.setSpeed(0);
  final g = c.state;
  for (final id in ['farm', 'sawmill', 'flax_field', 'ropewalk', 'warehouse',
    'pasture', 'hen_house']) {
    g.buildings.add(Building(defId: id)..workers = 2);
  }
  g.placeAll();
  g.population = 24;
  g.coin = 420;
  for (final r in [Resource.timber, Resource.planks, Resource.flax,
    Resource.grain, Resource.fish]) {
    g.stock[r] = 30;
  }
  for (var i = 0; i < 24 * 12; i++) {
    g.step();
    g.collectAll();
  }
  g.coin = 380;
  return c;
}

Future<void> open(WidgetTester tester, GameController c, String panel) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(PortsAhoyApp(controller: c));
  await tester.pumpAndSettle();
  await tester.tap(find.text(panel).last);
  await tester.pumpAndSettle();
}

/// The top edge of every card in the open panel, in order. Only the panel's:
/// the event banner at the top of the screen comes and goes with the weather,
/// and the panels are anchored below it, so it moves nothing in them.
List<double> cardTops(WidgetTester tester) => find
    .descendant(of: find.byType(Scrollable).last, matching: find.byType(Card))
    .evaluate()
    .map((e) => (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy)
    .toList();

Future<void> tick(WidgetTester tester, GameController c) async {
  c.act((s) {
    s.step();
    s.collectAll();
  });
  await tester.pump();
}

void main() {
  // A clock that only moves when told, for both holds.
  var now = DateTime(2026, 1, 1);
  setUp(() {
    now = DateTime(2026, 1, 1);
    HoldStill.now = () => now;
    MarketTab.now = () => now;
  });
  tearDown(() {
    HoldStill.now = DateTime.now;
    MarketTab.now = DateTime.now;
  });

  group('nothing moves on its own', () {
    // No touch at all, so no hold: the cards must keep their shape. Ticked
    // through the player's own act() so the panel rebuilds, but with the
    // scroll set by code rather than by a finger.
    for (final panel in ['Sheds', 'Trade', 'Build']) {
      testWidgets('on $panel, across five days of a struggling port',
          (tester) async {
        final c = await struggling();
        addTearDown(c.dispose);
        await open(tester, c, panel);
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .jumpTo(panel == 'Trade' ? 0 : 260);
        await tester.pumpAndSettle();
        // act() counts as an action and would refresh a hold anyway; with no
        // touch there is no hold, so this is the panel's own shape on trial.
        final first = cardTops(tester);
        for (var i = 0; i < 120; i++) {
          await tick(tester, c);
          expect(cardTops(tester), first,
              reason: 'something on $panel changed height at tick $i');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  testWidgets('the quay holds still while you trade, and then catches up',
      (tester) async {
    final c = await struggling();
    addTearDown(c.dispose);
    final g = c.state;
    g.market.ships
      ..clear()
      ..add(Ship(
          name: 'First Away',
          departTick: g.tick + 3,
          offers: [Offer(resource: Resource.planks, quantity: 40, pricePerUnit: 9)]))
      ..add(Ship(
          name: 'Second Hull',
          departTick: g.tick + 400,
          offers: [Offer(resource: Resource.timber, quantity: 40, pricePerUnit: 4)]));
    await open(tester, c, 'Quay');

    // The player touches the quay: a hold begins.
    await tester.tap(find.text('Second Hull'));
    await tester.pump();
    final before = tester.getTopLeft(find.text('Second Hull'));

    // The ship above sails.
    for (var i = 0; i < 5; i++) {
      await tick(tester, c);
    }
    expect(g.market.ships.any((s) => s.name == 'First Away'), isFalse);
    expect(find.text('First Away'), findsOneWidget,
        reason: 'a sailed ship keeps its place while the player is trading');
    expect(find.text('has sailed'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Second Hull')), before,
        reason: 'and the ship below it does not slide up under the thumb');

    // Nothing on a sailed ship can be done, on screen or in the game.
    final sailed = find.ancestor(
        of: find.text('First Away'), matching: find.byType(Card));
    for (final b in tester.widgetList<ButtonStyleButton>(find.descendant(
        of: sailed, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)))) {
      expect(b.onPressed, isNull);
    }

    // The player lets go; the quay catches up in one move.
    now = now.add(MarketTab.hold + const Duration(milliseconds: 1));
    await tester.pump(MarketTab.hold);
    expect(find.text('First Away'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a held panel still shows the player their own action',
      (tester) async {
    final c = await struggling();
    addTearDown(c.dispose);
    await open(tester, c, 'Sheds');
    // A touch starts a hold.
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -40));
    await tester.pump();
    final farm = c.state.shedsOfType('farm');
    final before = farm.fold(0, (a, b) => a + b.workers);
    c.act((s) => s.removeWorkerFrom('farm'));
    await tester.pump();
    final after = farm.fold(0, (a, b) => a + b.workers);
    expect(after, before - 1);
    expect(find.text('$after/${farm.first.def.maxWorkers * farm.length}'),
        findsOneWidget,
        reason: 'a hold freezes the game\'s ticks, never the player\'s taps');
    await tester.pumpWidget(const SizedBox());
  });

  test('a ship that has sailed cannot be traded with', () {
    // The Quay keeps a sailed ship on screen for a moment; the game must
    // refuse it regardless of what the screen shows.
    final g = GameState.newGame();
    g.stock[Resource.planks] = 50;
    g.coin = 1000;
    final ship = Ship(
        name: 'Gone',
        departTick: g.tick + 1,
        offers: [Offer(resource: Resource.planks, quantity: 20, pricePerUnit: 9)],
        wares: [Offer(resource: Resource.timber, quantity: 20, pricePerUnit: 2)]);
    g.market.ships.add(ship);
    g.tick += 2;
    expect(g.atQuay(ship), isFalse);
    expect(g.sell(ship, ship.offers.first, 10), 0);
    expect(g.buy(ship, ship.wares.first, 10), 0);
    expect(g.stock[Resource.planks], 50);
    expect(g.coin, 1000);
  });
}
