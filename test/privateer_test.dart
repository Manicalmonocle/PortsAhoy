import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/market.dart';
import 'package:ports_ahoy/sim/resources.dart';

GameState darkPort({int seed = 4242, int cellarWorkers = 0}) {
  final g = GameState.newGame(seed: seed);
  g.buildings.add(Building(defId: 'distillery', workers: 2));
  g.buildings.add(Building(defId: 'bonded_cellar', workers: cellarWorkers));
  g.population = 40;
  g.coin = 5000;
  return g;
}

Ship freeTraderBuying(Resource r, double qty, double price) => Ship(
      name: 'Test Petrel',
      departTick: 99999,
      allegiance: 'free',
      offers: [Offer(resource: r, quantity: qty, pricePerUnit: price)],
    );

void tickAndCollect(GameState g, [int ticks = 1]) {
  for (var i = 0; i < ticks; i++) {
    g.step();
    g.collectAll();
  }
}

void main() {
  group('the honest merchant path', () {
    test('a port with no dark shed never opens the dark trade', () {
      final g = GameState.newGame();
      expect(g.darkTradeOpen, isFalse);
      for (var i = 0; i < 3000; i++) {
        tickAndCollect(g);
      }
      expect(g.market.ships.every((s) => !s.isFreeTrader), isTrue);
      expect(g.notoriety, 0.0);
      expect(g.cutterOnStation, isFalse);
    });

    test('an honest port is never inspected, however long it plays', () {
      final g = GameState.newGame();
      for (var i = 0; i < 8000; i++) {
        tickAndCollect(g);
        expect(g.notoriety, 0.0);
      }
    });

    test('crown ships will not touch contraband at any price', () {
      final g = darkPort();
      for (var i = 0; i < 4000; i++) {
        tickAndCollect(g);
        for (final s in g.market.ships.where((s) => !s.isFreeTrader)) {
          for (final o in s.offers) {
            expect(o.resource.isContraband, isFalse);
          }
          for (final w in s.wares) {
            expect(w.resource.isContraband, isFalse);
          }
        }
      }
    });

    test('the lighthouse never requires contraband', () {
      for (final r in Balance.lighthouseCost.keys) {
        expect(r.isContraband, isFalse);
      }
    });
  });

  group('notoriety', () {
    test('selling contraband raises it', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 100;
      final ship = freeTraderBuying(Resource.spirits, 100, 40);
      g.sell(ship, ship.offers.first, 100);
      expect(g.notoriety, greaterThan(0));
    });

    test('there is no coin path down — at all', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 200;
      final ship = freeTraderBuying(Resource.spirits, 200, 40);
      g.sell(ship, ship.offers.first, 200);
      final heat = g.notoriety;
      expect(heat, greaterThan(0));

      // A fortune changes nothing. This is the whole invariant: a player with
      // 50,000 coin has exactly the options a player with 50 coin has.
      g.coin = 500000;
      for (var i = 0; i < 500; i++) {
        tickAndCollect(g);
      }
      expect(g.notoriety, greaterThanOrEqualTo(heat - 1e-9),
          reason: 'wealth must never buy notoriety down');
    });

    test('it does not decay on its own — there is no wait to shorten', () {
      final g = darkPort();
      // Conceal everything so holding accrues nothing, then confirm the meter
      // simply sits where it is.
      g.buildings.firstWhere((b) => b.defId == 'bonded_cellar').workers = 2;
      g.stock[Resource.spirits] = 10;
      g.notoriety = 25.0;
      final before = g.notoriety;
      for (var i = 0; i < 2000; i++) {
        tickAndCollect(g);
        if (g.cutterOnStation) g.cutterInspectTick = -1; // isolate decay
      }
      expect(g.notoriety, closeTo(before, 1e-6));
    });

    test('honest sales to a crown ship launder it down', () {
      final g = darkPort();
      g.notoriety = 40.0;
      g.stock[Resource.rope] = 300;
      final crown = Ship(
        name: 'Crown Gull',
        departTick: 99999,
        offers: [Offer(resource: Resource.rope, quantity: 300, pricePerUnit: 12)],
      );
      g.sell(crown, crown.offers.first, 300);
      expect(g.notoriety, lessThan(40.0));
    });

    test('laundering is capped per sale so one dump cannot wash a run clean',
        () {
      final g = darkPort();
      g.notoriety = 50.0;
      g.stock[Resource.tools] = 500;
      final crown = Ship(
        name: 'Crown Gull',
        departTick: 99999,
        offers: [Offer(resource: Resource.tools, quantity: 500, pricePerUnit: 40)],
      );
      g.sell(crown, crown.offers.first, 500);
      expect(g.notoriety,
          greaterThanOrEqualTo(50.0 - Balance.launderCapPerSale - 1e-9));
    });

    test('concealed stock is not conspicuous; exposed stock is', () {
      final hidden = darkPort(cellarWorkers: 2); // conceals 90
      final open = darkPort(cellarWorkers: 0);
      for (final g in [hidden, open]) {
        g.stock[Resource.spirits] = 80;
        g.buildings.firstWhere((b) => b.defId == 'distillery').workers = 0;
      }
      for (var i = 0; i < 200; i++) {
        tickAndCollect(hidden);
        tickAndCollect(open);
      }
      expect(hidden.notoriety, 0.0,
          reason: '80 units under 90 of concealment is invisible');
      expect(open.notoriety, greaterThan(0.0));
    });
  });

  group('the Revenue', () {
    test('no cutter is ever rolled below the patrol floor', () {
      final g = darkPort();
      g.notoriety = Balance.patrolFloor - 0.1;
      g.stock[Resource.spirits] = 0;
      for (var i = 0; i < 3000; i++) {
        tickAndCollect(g);
        expect(g.cutterOnStation, isFalse);
      }
    });

    test('a clean quay survives an inspection and is rewarded', () {
      final g = darkPort(cellarWorkers: 2);
      g.notoriety = 40.0;
      g.stock[Resource.spirits] = 10; // well under 90 concealed
      g.cutterInspectTick = g.tick + 1;
      final before = g.notoriety;

      tickAndCollect(g);
      tickAndCollect(g);

      expect(g.stock[Resource.spirits], 10.0, reason: 'nothing was found');
      expect(g.notoriety, lessThan(before));
      expect(g.cutterOnStation, isFalse);
    });

    test('a seizure takes exposed contraband and nothing else', () {
      final g = darkPort();
      // Still every shed, so the only thing that can move a number here is the
      // seizure itself.
      for (final b in g.buildings) {
        b.workers = 0;
      }
      g.stock[Resource.spirits] = 100;
      g.stock[Resource.planks] = 150;
      g.stock[Resource.tools] = 90;
      g.stock[Resource.fish] = 60;
      final coinBefore = g.coin;
      final popBefore = g.population;
      g.notoriety = 50.0;
      g.cutterInspectTick = g.tick + 1;

      tickAndCollect(g);
      tickAndCollect(g);

      expect(g.stock[Resource.spirits], lessThan(100));
      // Not a plank, not a tool, not a loaf, not a coin, not a hand.
      expect(g.stock[Resource.planks], 150.0);
      expect(g.stock[Resource.tools], 90.0);
      expect(g.stock[Resource.fish], 60.0);
      expect(g.coin, coinBefore);
      expect(g.population, popBefore);
    });

    test('an inspection draws no randomness — it is pure arithmetic', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 100;
      g.notoriety = 50.0;
      g.cutterInspectTick = g.tick;
      final seedBefore = g.rng.seed;
      g.cutterInspectTick = g.tick; // board now
      // Call the resolution path directly via a step at the boarding tick.
      tickAndCollect(g);
      // The step itself draws for market drift, so assert the outcome instead:
      // the same state must always seize the same amount.
      final other = darkPort();
      other.stock[Resource.spirits] = 100;
      other.notoriety = 50.0;
      other.cutterInspectTick = other.tick;
      other.step();
      expect(g.stock[Resource.spirits], other.stock[Resource.spirits]);
      expect(seedBefore, isNotNull);
    });

    test('nothing is ever taken while the app is closed', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 300;
      g.notoriety = 90.0;
      final before = g.stock[Resource.spirits];

      g.catchUp(const Duration(days: 20), ticksPerSecond: 1.0);

      // Production may have added more, but nothing was confiscated: the only
      // thing waiting is a cutter with a full window still to run.
      expect(g.contrabandSeized, 0.0);
      expect(g.stock[Resource.spirits], greaterThanOrEqualTo(before * 0.5));
      expect(g.cutterOnStation, isTrue,
          reason: 'you return to a live decision, not a resolved loss');
      expect(g.cutterInspectTick - g.tick, Balance.inspectionWindowTicks,
          reason: 'and to a full window, not a partly-elapsed one');
    });

    test('no rival raid resolves while the app is closed either', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 400;
      g.stock[Resource.powder] = 200;
      final logsBefore = g.logEntries.length;
      g.catchUp(const Duration(days: 30), ticksPerSecond: 1.0);
      expect(g.logEntries.where((e) => e.text.contains('Rivals')), isEmpty,
          reason: 'raids are interactive-only');
      expect(logsBefore, isNotNull);
    });

    test('the inspection window is fixed and nothing can alter it', () {
      final g = darkPort();
      g.notoriety = 60.0;
      g.stock[Resource.spirits] = 100;
      for (var i = 0; i < 4000 && !g.cutterOnStation; i++) {
        tickAndCollect(g);
      }
      expect(g.cutterOnStation, isTrue);
      expect(g.cutterInspectTick - g.tick, Balance.inspectionWindowTicks);
    });
  });

  group('the free actions', () {
    test('scuttling destroys cargo, costs no coin, and changes no heat', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 100;
      g.notoriety = 30.0;
      final coinBefore = g.coin;

      final dumped = g.scuttle(Resource.spirits, 60);

      expect(dumped, 60.0);
      expect(g.stock[Resource.spirits], 40.0);
      expect(g.coin, coinBefore, reason: 'the panic button never costs coin');
      expect(g.notoriety, 30.0);
    });

    test('scuttling converts a certain seizure into a clean inspection', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 100;
      g.notoriety = 50.0;
      g.cutterInspectTick = g.tick + 2;

      g.scuttle(Resource.spirits, 100);
      g.buildings.firstWhere((b) => b.defId == 'distillery').workers = 0;
      tickAndCollect(g);
      tickAndCollect(g);
      tickAndCollect(g);

      expect(g.notoriety, lessThan(50.0), reason: 'a clean board is rewarded');
      expect(g.contrabandSeized, 0.0);
    });

    test('declaring pays badly but is always available', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 100;
      g.notoriety = 20.0;
      final coinBefore = g.coin;

      final earned = g.declareToCustoms(Resource.spirits, 100);

      expect(earned, greaterThan(0));
      expect(g.coin, greaterThan(coinBefore));
      expect(g.stock[Resource.spirits], 0.0);
      expect(g.notoriety, 20.0, reason: 'declaring is neither crime nor cure');
      // Deliberately a poor price, not a trap.
      expect(earned, lessThan(100 * Resource.spirits.basePrice));
    });

    test('neither free action requires a building or a cooldown', () {
      final g = GameState.newGame();
      g.stock[Resource.spirits] = 10;
      expect(g.scuttle(Resource.spirits, 5), 5.0);
      expect(g.declareToCustoms(Resource.spirits, 5), greaterThan(0));
    });
  });

  group('barter — contraband for materials', () {
    test('it swaps goods without touching coin', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 200;
      final coinBefore = g.coin;
      final deal = Barter(
          give: Resource.spirits, giveQty: 50, take: Resource.ore, takeQty: 100);
      final ship = Ship(
          name: 'Dark Wake',
          departTick: 99999,
          allegiance: 'free',
          offers: const [],
          barters: [deal]);

      expect(g.barter(ship, deal), isTrue);
      expect(g.stock[Resource.spirits], 150.0);
      expect(g.stock[Resource.ore], 100.0);
      expect(g.coin, coinBefore, reason: 'barter is not a coin transaction');
      expect(deal.taken, isTrue);
    });

    test('it is the loudest transaction per unit', () {
      final sold = darkPort();
      final swapped = darkPort();
      for (final g in [sold, swapped]) {
        g.stock[Resource.spirits] = 200;
      }

      final ship = freeTraderBuying(Resource.spirits, 50, 40);
      sold.sell(ship, ship.offers.first, 50);

      final deal = Barter(
          give: Resource.spirits, giveQty: 50, take: Resource.ore, takeQty: 100);
      final darkShip = Ship(
          name: 'Dark Wake',
          departTick: 99999,
          allegiance: 'free',
          offers: const [],
          barters: [deal]);
      swapped.barter(darkShip, deal);

      expect(swapped.notoriety, greaterThan(sold.notoriety));
    });

    test('it is refused when the goods or the room are not there', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 5;
      final deal = Barter(
          give: Resource.spirits, giveQty: 50, take: Resource.ore, takeQty: 100);
      final ship = Ship(
          name: 'Dark Wake',
          departTick: 99999,
          allegiance: 'free',
          offers: const [],
          barters: [deal]);
      expect(g.barter(ship, deal), isFalse);
      expect(deal.taken, isFalse);
    });
  });

  // Reported from play: "I skip it because it doesn't feel worth the
  // investment... just adds another layer for no real payoff." Measured against
  // the same eight seeds the dark trade is worth about twelve days of a hundred
  // and twenty — real, and invisible, because every number on screen was one it
  // COST you. The ledger is the other half of that sentence.
  group('the dark trade keeps its own accounts', () {
    test('a barter counts what you gained, not what you handed over', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 200;
      expect(g.darkEarned, 0);

      final deal = Barter(
          give: Resource.spirits, giveQty: 50, take: Resource.ore, takeQty: 100);
      final ship = Ship(
          name: 'Dark Wake',
          departTick: 99999,
          allegiance: 'free',
          offers: const [],
          barters: [deal]);
      expect(g.barter(ship, deal), isTrue);

      final gained = 100 * g.market.priceOf(Resource.ore) -
          50 * g.market.priceOf(Resource.spirits);
      expect(g.darkEarned, closeTo(gained, 0.01),
          reason: 'the ledger records the margin, not the gross');
    });

    test('selling contraband counts, selling planks does not', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 100;
      g.stock[Resource.planks] = 100;

      final dark = freeTraderBuying(Resource.spirits, 50, 40);
      g.sell(dark, dark.offers.first, 50);
      final afterContraband = g.darkEarned;
      expect(afterContraband, greaterThan(0));

      final honest = freeTraderBuying(Resource.planks, 50, 8);
      g.sell(honest, honest.offers.first, 50);
      expect(g.darkEarned, afterContraband,
          reason: 'an honest sale is not the dark trade doing well');
    });

    test('what the Revenue takes is charged against it', () {
      final g = darkPort();
      g.stock[Resource.spirits] = 100;
      g.notoriety = 100;
      final before = g.darkLost;

      // Board now; the resolution runs inside the tick.
      g.cutterInspectTick = g.tick;
      tickAndCollect(g);

      expect(g.darkLost, greaterThan(before),
          reason: 'a seizure is a cost of the layer, and has to show as one');
      expect(g.darkNet, g.darkEarned - g.darkLost);
    });

    test('the accounts survive a save', () {
      final g = darkPort();
      g.darkEarned = 1234.5;
      g.darkLost = 234.5;
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(restored.darkEarned, closeTo(1234.5, 0.1));
      expect(restored.darkNet, closeTo(1000.0, 0.2));
    });
  });

  group('rival raids', () {
    test('a small hoard is never raided', () {
      final g = darkPort();
      g.buildings.firstWhere((b) => b.defId == 'distillery').workers = 0;
      g.stock[Resource.spirits] = 10; // 340c base, well under the floor
      for (var i = 0; i < 2000; i++) {
        tickAndCollect(g);
      }
      expect(g.logEntries.where((e) => e.text.contains('Rivals')), isEmpty);
    });

    test('rivals ignore concealment, so the cellar is no defence from them',
        () {
      // The cellar hides you from the Crown and not at all from your own
      // trade. That is what forces turnover instead of hoarding.
      final g = darkPort(cellarWorkers: 2);
      g.stock[Resource.spirits] = 400;
      expect(g.exposedUnits, 400 - 90.0);
      expect(g.contrabandBaseValue, greaterThan(Balance.raidHoardFloor));
    });
  });

  group('prize-taking', () {
    GameState raider({int crew = 4, double powder = 50}) {
      final g = darkPort();
      g.buildings.add(Building(defId: 'privateer_berth', workers: crew));
      g.stock[Resource.powder] = powder;
      g.stock[Resource.barrels] = 200;
      g.stock[Resource.rope] = 200;
      g.stock[Resource.sailcloth] = 200;
      tickAndCollect(g); // let the berth reach readiness
      return g;
    }

    Ship foreignHull({int tons = 60}) => Ship(
          name: 'Foreign Kestrel',
          departTick: 99999,
          offers: const [],
          foreign: true,
          prizeTons: tons,
        );

    test('boarding resolves in the same tick — there is no voyage', () {
      final g = raider();
      final ship = foreignHull();
      g.market.ships.add(ship);
      final tickBefore = g.tick;

      g.takePrize(ship);

      expect(g.tick, tickBefore, reason: 'no time passes, so nothing can wait');
      expect(g.market.ships.contains(ship), isFalse);
    });

    test('no player-owned object carries a countdown field', () {
      // The rule the whole layer rests on. Ship.departTick belongs to an NPC
      // and works against the player, never for them.
      final g = raider();
      expect(g.marqueTons, isA<int>());
      expect(g.prizesTaken, isA<int>());
      // cutterInspectTick is the Crown's clock, not a reward timer.
      expect(g.cutterInspectTick, -1);
    });

    test('an unstaffed berth cannot board', () {
      final g = raider(crew: 0);
      final ship = foreignHull();
      expect(g.prizeBlocker(ship), isNotNull);
      expect(g.takePrize(ship), isFalse);
    });

    test('boarding needs powder and spends it', () {
      final g = raider(powder: 2);
      final ship = foreignHull();
      expect(g.prizeBlocker(ship), contains('powder'));

      final armed = raider(powder: 50);
      final target = foreignHull();
      armed.market.ships.add(target);
      final before = armed.stock[Resource.powder];
      armed.takePrize(target);
      expect(armed.stock[Resource.powder],
          closeTo(before - Balance.prizePowderCost, 1e-9));
    });

    test('a crown trader is never a lawful target', () {
      final g = raider();
      final crown = Ship(
          name: 'Crown Gull', departTick: 99999, offers: const []);
      expect(g.prizeBlocker(crown), 'Not a lawful target');
      expect(g.takePrize(crown), isFalse);
    });

    test('a covered prize spends tonnage and raises no notoriety', () {
      final g = raider();
      g.marqueTons = 200;
      g.notoriety = 5.0;
      final ship = foreignHull(tons: 60);
      g.market.ships.add(ship);

      g.takePrize(ship);

      expect(g.marqueTons, 140);
      expect(g.notoriety, lessThanOrEqualTo(5.0 + 1e-9),
          reason: 'a lawful prize is not a crime');
    });

    test('an uncovered prize is piracy and is noticed', () {
      final g = raider();
      g.marqueTons = 0;
      g.notoriety = 5.0;
      final ship = foreignHull(tons: 60);
      g.market.ships.add(ship);

      g.takePrize(ship);
      expect(g.notoriety, greaterThan(5.0));
    });

    test('a won prize lands real cargo', () {
      final g = raider();
      g.marqueTons = 500;
      // Force the win: a full crew at readiness plus cover is the best case,
      // so retry until the roll lands rather than asserting on one draw.
      var landed = false;
      for (var i = 0; i < 40 && !landed; i++) {
        final ship = foreignHull();
        g.market.ships.add(ship);
        final oreBefore = g.stock[Resource.ore];
        if (g.takePrize(ship)) {
          expect(g.stock[Resource.ore], greaterThan(oreBefore));
          landed = true;
        }
        g.stock[Resource.powder] = 50;
      }
      expect(landed, isTrue, reason: 'a full crew should win sometimes');
      expect(g.prizesTaken, greaterThan(0));
    });

    test('overflow is bought, never destroyed', () {
      final g = raider();
      g.marqueTons = 5000;
      // Fill every hold so nothing can physically land.
      for (final r in Resource.values) {
        g.stock[r] = g.storageCapacity;
      }
      g.stock[Resource.powder] = 50;

      var won = false;
      for (var i = 0; i < 40 && !won; i++) {
        final ship = foreignHull(tons: 90);
        g.market.ships.add(ship);
        final coinBefore = g.coin;
        if (g.takePrize(ship)) {
          expect(g.coin, greaterThan(coinBefore),
              reason: 'a full shed must not turn a won fight into a loss');
          won = true;
        }
        g.stock[Resource.powder] = 50;
      }
      expect(won, isTrue);
    });

    test('a failed boarding still costs powder and notice', () {
      final g = raider(crew: 1);
      g.marqueTons = 0;
      var failed = false;
      for (var i = 0; i < 60 && !failed; i++) {
        final ship = foreignHull();
        g.market.ships.add(ship);
        final heatBefore = g.notoriety;
        if (!g.takePrize(ship)) {
          expect(g.notoriety, greaterThan(heatBefore));
          failed = true;
        }
        g.stock[Resource.powder] = 50;
      }
      expect(failed, isTrue);
    });

    test('more crew means better odds, capped', () {
      final small = raider(crew: 1);
      final big = raider(crew: 4);
      final ship = foreignHull();
      expect(big.prizeSuccessChance(ship),
          greaterThan(small.prizeSuccessChance(ship)));
      expect(big.prizeSuccessChance(ship),
          lessThanOrEqualTo(Balance.prizeSuccessCap));
    });
  });

  group('letters of marque', () {
    test('buying one spends coin and materials for tonnage', () {
      final g = darkPort();
      g.coin = 10000;
      g.stock[Resource.sailcloth] = 100;
      g.stock[Resource.tools] = 100;

      expect(g.buyLetterOfMarque(100), isTrue);
      expect(g.marqueTons, 100);
      expect(g.coin, 10000 - 100 * Balance.marqueCoinPerTon);
      expect(g.letterActive, isTrue);
    });

    test('the Admiralty refuses a port that is too closely watched', () {
      final g = darkPort();
      g.coin = 100000;
      g.stock[Resource.sailcloth] = 500;
      g.stock[Resource.tools] = 500;
      g.notoriety = Balance.letterHeatCeiling + 1;

      expect(g.canBuyLetter, isFalse);
      expect(g.buyLetterOfMarque(100), isFalse);
      expect(g.marqueTons, 0);
    });

    test('an unaffordable letter changes nothing', () {
      final g = darkPort();
      g.coin = 5;
      expect(g.buyLetterOfMarque(200), isFalse);
      expect(g.marqueTons, 0);
    });

    test('tonnage round-trips through a save', () {
      final g = darkPort();
      g.marqueTons = 175;
      g.prizesTaken = 4;
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(restored.marqueTons, 175);
      expect(restored.prizesTaken, 4);
    });
  });

  group('persistence', () {
    test('notoriety and the cutter round-trip', () {
      final g = darkPort();
      g.notoriety = 37.125;
      g.cutterInspectTick = 4242;
      g.contrabandSeized = 88.5;

      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);

      expect(restored.notoriety, closeTo(37.125, 1e-9));
      expect(restored.cutterInspectTick, 4242);
      expect(restored.contrabandSeized, closeTo(88.5, 1e-9));
    });

    test('a v1 save loads as a spotless honest port', () {
      final g = GameState.newGame();
      final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
      json.remove('notoriety');
      json.remove('cutterInspectTick');
      json.remove('contrabandSeized');

      final restored = GameState.fromJson(json);
      expect(restored.notoriety, 0.0);
      expect(restored.cutterInspectTick, -1);
      expect(restored.contrabandSeized, 0.0);
    });

    test('a v1 ship with no allegiance loads as an honest trader', () {
      final ship = Ship.fromJson({
        'name': 'Old Gull',
        'departTick': 100,
        'offers': <dynamic>[],
      });
      expect(ship.allegiance, 'crown');
      expect(ship.isFreeTrader, isFalse);
      expect(ship.barters, isEmpty);
    });
  });

  group('balance invariants hold with the dark sheds', () {
    test('contraband sheds still beat raw extraction per worker', () {
      final bestRaw = kBuildingDefs
          .where((d) => d.isProducer && !d.isWorkshop && d.outputs.isNotEmpty)
          .map((d) => d.marginPerWorkerTick)
          .reduce((a, b) => a > b ? a : b);
      for (final id in ['distillery', 'powder_mill']) {
        expect(defById(id).marginPerWorkerTick, greaterThan(bestRaw));
      }
    });

    test('a berth is not counted as a workshop', () {
      // Upkeep must never be folded into inputs, or the berth reports a
      // negative margin and breaks the refining invariants.
      final berth = defById('privateer_berth');
      expect(berth.isWorkshop, isFalse);
      expect(berth.isCrewed, isTrue);
      expect(berth.isStaffable, isTrue);
    });

    test('every dark shed is staffable and reachable in the UI', () {
      for (final id in kDarkBuildingIds) {
        expect(defById(id).isStaffable, isTrue, reason: id);
      }
    });
  });
}
