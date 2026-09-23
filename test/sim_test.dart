import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/market.dart';
import 'package:ports_ahoy/sim/resources.dart';

/// Advance a tick and cart every yard into the stores — which is exactly what
/// production did implicitly before sheds held their own output.
void tickAndCollect(GameState g, [int ticks = 1]) {
  for (var i = 0; i < ticks; i++) {
    g.step();
    g.collectAll();
  }
}


/// Maturity lives on the building now, not the port. Tests that used to set
/// `g.grangeMaturity` reach through to the shed it actually belongs to.
void ripenGrange(GameState g, double v) {
  for (final b in g.buildings) {
    if (b.defId == 'grange') b.maturity = v;
  }
}

void main() {
  group('production', () {
    test('extractors produce without inputs', () {
      final g = GameState.newGame();
      final before = g.stock[Resource.timber];
      tickAndCollect(g);
      expect(g.stock[Resource.timber], greaterThan(before));
    });

    test('a workshop with no input stalls at zero efficiency', () {
      final g = GameState.newGame();
      g.stock[Resource.flax] = 0;
      g.buildings.add(Building(defId: 'ropewalk', workers: 2));
      tickAndCollect(g);
      final ropewalk = g.buildings.firstWhere((b) => b.defId == 'ropewalk');
      expect(ropewalk.lastEfficiency, 0.0);
      expect(g.stock[Resource.rope], 0.0);
    });

    test('a workshop consumes inputs and yields outputs', () {
      final g = GameState.newGame();
      g.stock[Resource.flax] = 100;
      g.buildings.add(Building(defId: 'ropewalk', workers: 2));
      tickAndCollect(g);
      expect(g.stock[Resource.flax], lessThan(100));
      expect(g.stock[Resource.rope], closeTo(0.4, 1e-9)); // 0.20 * 2 workers
    });

    test('partial input supply yields partial output, never negative stock', () {
      final g = GameState.newGame();
      g.stock[Resource.flax] = 0.25; // half of what 2 workers need (0.50)
      g.buildings.add(Building(defId: 'ropewalk', workers: 2));
      tickAndCollect(g);
      expect(g.stock[Resource.flax], closeTo(0.0, 1e-9));
      expect(g.stock[Resource.rope], closeTo(0.2, 1e-9)); // 0.20 * 2 * 50%
    });

    test('production stops at the storage cap', () {
      final g = GameState.newGame();
      g.stock[Resource.timber] = g.storageCapacity;
      tickAndCollect(g);
      expect(g.stock[Resource.timber], lessThanOrEqualTo(g.storageCapacity + 1e-9));
    });
  });

  group('town upkeep', () {
    test('the town eats at day end, sea first', () {
      final g = GameState.newGame();
      final fishBefore = g.stock[Resource.fish];
      for (var i = 0; i < Balance.ticksPerDay; i++) {
        tickAndCollect(g);
      }
      expect(g.stock[Resource.fish], lessThan(fishBefore + 100));
      expect(g.day, 2);
    });

    test('starvation costs population and frees its worker slot', () {
      final g = GameState.newGame();
      for (final r in Resource.values.where((r) => r.isFood)) {
        g.stock[r] = 0;
      }
      for (final b in g.buildings) {
        if (b.def.id == 'fishing_wharf' || b.def.id == 'farm') b.workers = 0;
      }
      final popBefore = g.population;
      for (var i = 0; i < Balance.ticksPerDay; i++) {
        tickAndCollect(g);
      }
      expect(g.population, lessThan(popBefore));
      expect(g.assignedWorkers, lessThanOrEqualTo(g.population));
    });

    test('wages are drawn at day end', () {
      final g = GameState.newGame();
      final coinBefore = g.coin;
      final bill = g.dailyWageBill;
      for (var i = 0; i < Balance.ticksPerDay; i++) {
        tickAndCollect(g);
      }
      expect(g.coin, coinBefore - bill);
    });

    test('population never exceeds housing', () {
      final g = GameState.newGame();
      for (var i = 0; i < Balance.ticksPerDay * 60; i++) {
        g.stock[Resource.fish] = 200;
        g.coin = 99999;
        tickAndCollect(g);
      }
      expect(g.population, lessThanOrEqualTo(g.housingCapacity));
    });

    // Reported from play twice: "day 10 I hit 9 population then stagnant until
    // day 21 while staying above the limits". Growth used to be a daily coin
    // flip, which averages correctly and still produces dead fortnights. It now
    // accumulates, so a fed and solvent port must never stall for long.
    //
    // This test exists because the accumulating version was once written and
    // silently did not apply — the suite passed, the average was right, and the
    // stall survived. Asserting the *gap* is what catches that.
    test('a fed, solvent port grows steadily with no long stalls', () {
      for (final seed in [1, 2, 3, 777, 4242, 8675309]) {
        final g = GameState.newGame(seed: seed);
        g.buildings.add(Building(defId: 'house'));
        g.placeAll();

        var stalled = 0, longest = 0, last = g.population;
        for (var d = 1; d <= 40; d++) {
          for (var t = 0; t < Balance.ticksPerDay; t++) {
            tickAndCollect(g);
          }
          g.coin = 5000;
          g.stock[Resource.fish] = 300;
          if (g.population >= g.housingCapacity) break;

          if (g.population == last) {
            stalled++;
            if (stalled > longest) longest = stalled;
          } else {
            stalled = 0;
          }
          last = g.population;
        }
        expect(longest, lessThanOrEqualTo(2),
            reason: 'seed $seed stalled $longest days while fed and solvent');
      }
    });
  });

  group('the run journal', () {
    // The balance bot has been wrong twice in ways only real play caught, and
    // guessing at how a person plays did not fix it. This is the trace a real
    // run hands over so the bot can be lined up against it.
    test('records a row a day and the moments worth knowing', () {
      final g = GameState.newGame(seed: 7);
      for (var d = 0; d < 20; d++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          tickAndCollect(g);
        }
      }

      expect(g.journal.days, isNotEmpty);
      expect(g.journal.days.length, greaterThanOrEqualTo(19),
          reason: 'one row per day');
      expect(g.journal.days.map((d) => d.day).toSet().length,
          g.journal.days.length,
          reason: 'no day recorded twice');

      // A build is a moment worth knowing the day of.
      g.coin = 9999;
      g.stock[Resource.planks] = 500;
      final before = g.journal.marks.length;
      g.build(defById('fishing_wharf'));
      expect(g.journal.marks.length, before + 1);
      expect(g.journal.marks.last.what, contains('Fishing Wharf'));
    });

    test('the trace survives a save, or a long run loses its own history', () {
      final g = GameState.newGame(seed: 7);
      for (var d = 0; d < 6; d++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          tickAndCollect(g);
        }
      }
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);

      expect(restored.journal.days.length, g.journal.days.length);
      expect(restored.journal.days.last.toCsv(), g.journal.days.last.toCsv());
    });

    test('a report is small enough to paste', () {
      final g = GameState.newGame(seed: 7);
      for (var d = 0; d < 40; d++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          tickAndCollect(g);
        }
      }
      final text =
          g.journal.report(charters: 'poor_soil', difficulty: 1, won: false);
      expect(text, contains('day,pop,coin,built,staffed,foodDays,atSea'));
      expect(text, contains('poor_soil'));
      // Roughly 30 bytes a day; a 400-day cap must stay well inside a message.
      expect(text.length / g.journal.days.length, lessThan(60));
    });
  });

  group('worker assignment', () {
    test('cannot assign more workers than are idle', () {
      final g = GameState.newGame();
      g.buildings.add(Building(defId: 'smithy'));
      final idx = g.buildings.length - 1;
      final idle = g.idleWorkers;

      // Asking for one more than the town has spare must be refused outright,
      // not silently partially filled.
      expect(g.setWorkers(idx, idle + 1), isFalse);
      expect(g.buildings[idx].workers, 0);

      expect(g.setWorkers(idx, idle), isTrue);
      expect(g.idleWorkers, 0);
      expect(g.assignedWorkers, g.population);
    });

    test('assignment is clamped to the building maximum', () {
      final g = GameState.newGame();
      g.population = 50;
      g.buildings.add(Building(defId: 'smithy'));
      g.setWorkers(g.buildings.length - 1, 99);
      expect(g.buildings.last.workers, defById('smithy').maxWorkers);
    });
  });

  group('market', () {
    test('bulk selling depresses the price index', () {
      final m = Market();
      final before = m.index[Resource.rope]!;
      m.applySalePressure(Resource.rope, 300);
      expect(m.index[Resource.rope]!, lessThan(before));
    });

    test('prices mean-revert toward 1.0 over time', () {
      final m = Market();
      final rng = SeededRng(7);
      m.index[Resource.rope] = 0.5;
      for (var i = 1; i <= 600; i++) {
        m.advance(i, rng);
      }
      expect(m.index[Resource.rope]!, greaterThan(0.75));
    });

    test('ships arrive and the port never overfills', () {
      final g = GameState.newGame();
      for (var i = 0; i < 500; i++) {
        tickAndCollect(g);
      }
      expect(g.market.ships.length, lessThanOrEqualTo(Market.maxShipsInPort));
      expect(g.market.ships, isNotEmpty);
    });

    test('selling moves goods for coin and cannot oversell', () {
      final g = GameState.newGame();
      g.stock[Resource.rope] = 10;
      final ship = Ship(
        name: 'Test Gull',
        departTick: 999,
        offers: [Offer(resource: Resource.rope, quantity: 50, pricePerUnit: 12)],
      );
      final earned = g.sell(ship, ship.offers.first, 999);
      expect(earned, closeTo(120, 1e-9)); // capped by the 10 in stock
      expect(g.stock[Resource.rope], 0.0);
      expect(ship.offers.first.quantity, 40.0);
    });
  });

  group('buying from ships', () {
    Ship shipSelling(Resource r, double qty, double price) => Ship(
          name: 'Test Petrel',
          departTick: 999,
          offers: const [],
          wares: [Offer(resource: r, quantity: qty, pricePerUnit: price)],
        );

    test('buying spends coin and lands the goods', () {
      final g = GameState.newGame();
      g.coin = 1000;
      final ship = shipSelling(Resource.planks, 50, 8);
      final before = g.stock[Resource.planks];
      final spent = g.buy(ship, ship.wares.first, 20);

      expect(spent, closeTo(160, 1e-9));
      expect(g.coin, 840);
      expect(g.stock[Resource.planks], closeTo(before + 20, 1e-9));
      expect(ship.wares.first.quantity, 30);
    });

    test('a purchase is capped by coin and never overdraws', () {
      final g = GameState.newGame();
      g.coin = 50;
      final ship = shipSelling(Resource.planks, 100, 10);
      final before = g.stock[Resource.planks];
      g.buy(ship, ship.wares.first, 100);

      expect(g.coin, greaterThanOrEqualTo(0));
      // 50 coin at 10 apiece buys five.
      expect(g.stock[Resource.planks], closeTo(before + 5, 1e-9));
    });

    test('a purchase is capped by remaining storage', () {
      final g = GameState.newGame();
      g.coin = 100000;
      g.stock[Resource.ore] = g.storageCapacity - 10;
      final ship = shipSelling(Resource.ore, 500, 1);
      g.buy(ship, ship.wares.first, 500);

      expect(g.stock[Resource.ore], closeTo(g.storageCapacity, 1e-6));
    });

    test('buying lifts the price index, the mirror of selling', () {
      final g = GameState.newGame();
      g.coin = 100000;
      final before = g.market.index[Resource.ore]!;
      final ship = shipSelling(Resource.ore, 300, 5);
      g.buy(ship, ship.wares.first, 300);

      expect(g.market.index[Resource.ore]!, greaterThan(before));
    });

    test('a ship that has sold and bought everything leaves', () {
      final ship = Ship(
        name: 'Spent Wake',
        departTick: 999,
        offers: [Offer(resource: Resource.rope, quantity: 0, pricePerUnit: 1)],
        wares: [Offer(resource: Resource.ore, quantity: 0, pricePerUnit: 1)],
      );
      expect(ship.isSpent, isTrue);
    });

    test('coin is not a dead end — materials are always reachable', () {
      // The failure this guards against: a rich port with no planks and no way
      // to build its way back out. Ships must eventually carry raw cargo.
      final g = GameState.newGame();
      var sawWares = false;
      for (var i = 0; i < 2000 && !sawWares; i++) {
        tickAndCollect(g);
        sawWares = g.market.ships.any((s) => s.wares.isNotEmpty);
      }
      expect(sawWares, isTrue);
    });
  });

  group('the import berth (coin sink)', () {
    GameState withBerth({int workers = 3, Resource cargo = Resource.timber}) {
      final g = GameState.newGame();
      g.buildings.add(Building(
          defId: 'import_berth', workers: workers, importResource: cargo));
      g.population = 40;
      return g;
    }

    test('spends coin and lands cargo in the same tick', () {
      final g = withBerth();
      g.coin = 5000;
      final coinBefore = g.coin;
      final timberBefore = g.stock[Resource.timber];

      tickAndCollect(g);

      expect(g.coin, lessThan(coinBefore), reason: 'coin should be spent');
      expect(g.stock[Resource.timber], greaterThan(timberBefore),
          reason: 'cargo lands the same tick it is paid for');
    });

    test('there is no delay to sell a skip against', () {
      // The whole anti-timer argument rests on this: paying and receiving are
      // the same instant, so no duration exists that money could shorten.
      final g = withBerth();
      g.coin = 5000;
      final before = g.stock[Resource.timber];
      tickAndCollect(g);
      expect(g.stock[Resource.timber], greaterThan(before));
    });

    test('an unstaffed berth spends nothing', () {
      final g = withBerth(workers: 0);
      g.coin = 5000;
      tickAndCollect(g);
      expect(g.coin, 5000);
    });

    test('it never spends into the wage cushion', () {
      final g = withBerth();
      g.coin = 40;
      tickAndCollect(g);
      expect(g.coin, greaterThanOrEqualTo(0));
      // With a cushion of 3 days' wages, a near-empty treasury imports nothing.
      expect(g.coin, 40);
    });

    test('it stops at the storage cap rather than burning coin', () {
      final g = withBerth();
      g.coin = 100000;
      g.stock[Resource.timber] = g.storageCapacity;
      final coinBefore = g.coin;
      tickAndCollect(g);
      expect(g.stock[Resource.timber],
          lessThanOrEqualTo(g.storageCapacity + 1e-6));
      expect(g.coin, coinBefore, reason: 'no room means no purchase');
    });

    test('leaning on one cargo raises its price against you', () {
      final g = withBerth();
      g.coin = 100000;
      final before = g.market.index[Resource.timber]!;
      for (var i = 0; i < 30; i++) {
        g.stock[Resource.timber] = 0; // keep room so the berth keeps buying
        tickAndCollect(g);
      }
      expect(g.market.index[Resource.timber]!, greaterThan(before),
          reason: 'sustained importing should walk the price up');
    });

    test('coin can only buy raws, never a finished good', () {
      // Every plank, rope, sailcloth and tool in the win condition must still
      // pass through a shed the player built and staffed.
      for (final r in kImportables) {
        expect(r.category, ResourceCategory.raw,
            reason: '${r.label} must not be importable');
      }
      expect(kImportables.contains(Resource.grain), isFalse,
          reason: 'coin must not be an escape from a famine');
    });

    test('an int treasury stays exact over a long run', () {
      final g = withBerth();
      g.coin = 60000;
      for (var i = 0; i < 500; i++) {
        g.stock[Resource.timber] = 0;
        tickAndCollect(g);
      }
      expect(g.coin, isA<int>());
      expect(g.coin, greaterThanOrEqualTo(0));
    });

    test('the chosen cargo round-trips through a save', () {
      final g = withBerth(cargo: Resource.ore);
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      final berth =
          restored.buildings.firstWhere((b) => b.defId == 'import_berth');
      expect(berth.importResource, Resource.ore);
    });
  });

  group('construction', () {
    test('building deducts coin and materials', () {
      final g = GameState.newGame();
      final def = defById('sawmill');
      g.coin = 500;
      g.stock[Resource.timber] = 100;
      g.unlocked.add(def.id); // the tree gates it; this test is about cost
      final coinBefore = g.coin;
      expect(g.build(def), isTrue);
      expect(g.coin, coinBefore - def.coinCost);
      expect(g.stock[Resource.timber], 100 - def.cost[Resource.timber]!);
    });

    test('building is refused when unaffordable and changes nothing', () {
      final g = GameState.newGame();
      g.coin = 0;
      final count = g.buildings.length;
      expect(g.build(defById('smithy')), isFalse);
      expect(g.buildings.length, count);
    });

    test('the lighthouse requires the full project cost', () {
      final g = GameState.newGame();
      expect(g.canBuildLighthouse, isFalse);
      g.coin = Balance.lighthouseCoin;
      Balance.lighthouseCost.forEach((r, q) => g.stock[r] = q);
      expect(g.buildLighthouse(), isTrue);
      expect(g.lighthouseBuilt, isTrue);
      expect(g.coin, 0);
    });
  });

  group('persistence', () {
    test('a save round-trips through JSON exactly', () {
      final g = GameState.newGame();
      for (var i = 0; i < 300; i++) {
        tickAndCollect(g);
      }
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);

      expect(restored.tick, g.tick);
      expect(restored.coin, g.coin);
      expect(restored.population, g.population);
      expect(restored.buildings.length, g.buildings.length);
      expect(restored.stock[Resource.timber],
          closeTo(g.stock[Resource.timber], 1e-3));
      expect(restored.market.ships.length, g.market.ships.length);
    });

    test('a restored game continues the same world deterministically', () {
      final a = GameState.newGame();
      for (var i = 0; i < 100; i++) {
        a.step();
      }
      final b = GameState.fromJson(
          jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);

      for (var i = 0; i < 50; i++) {
        a.step();
        b.step();
      }
      expect(b.coin, a.coin);
      expect(b.population, a.population);
      expect(b.stock[Resource.timber], closeTo(a.stock[Resource.timber], 1e-6));
    });
  });

  group('offline progress', () {
    test('catch-up advances the world and is bounded in compute', () {
      final g = GameState.newGame();
      final ticks = g.catchUp(const Duration(days: 30), ticksPerSecond: 1.0);
      expect(ticks, Balance.maxCatchUpTicks);
      expect(g.tick, Balance.maxCatchUpTicks);
    });

    test('storage — not a paywall — is what bounds time away', () {
      final g = GameState.newGame();
      g.coin = 100000;
      g.catchUp(const Duration(hours: 500), ticksPerSecond: 1.0);
      for (final r in Resource.values) {
        expect(g.stock[r], lessThanOrEqualTo(g.storageCapacity + 1e-6),
            reason: '${r.label} exceeded storage');
      }
    });
  });

  group('balance invariants', () {
    test('refining beats selling the raw inputs it consumes', () {
      for (final def in kBuildingDefs.where((d) => d.isWorkshop)) {
        expect(def.marginPerWorkerTick, greaterThan(0),
            reason: '${def.name} destroys value at neutral prices');
      }
    });

    test('the deepest chain pays the best per worker-tick', () {
      final smithy = defById('smithy').marginPerWorkerTick;
      final ropewalk = defById('ropewalk').marginPerWorkerTick;
      expect(smithy, greaterThan(ropewalk));
    });

    test('every workshop beats the best raw extractor per worker', () {
      // The bar is the *best* extractor, not the worst: refining has to be
      // worth the capital and the extra worker, or players correctly ignore it.
      final bestRaw = kBuildingDefs
          .where((d) => d.isProducer && !d.isWorkshop)
          .map((d) => d.marginPerWorkerTick)
          .reduce((a, b) => a > b ? a : b);

      for (final def in kBuildingDefs.where((d) => d.isWorkshop)) {
        expect(def.marginPerWorkerTick, greaterThan(bestRaw),
            reason: '${def.name} is not worth staffing over raw extraction');
      }
    });

    test('rope is contested between the lighthouse and the sails', () {
      // THE PORT'S OLDEST DECISION, MOVED DOWNSTREAM. Flax used to feed both
      // the ropewalk and the weaver, and splitting one field between them was
      // the choice the lighthouse's own comment calls the most interesting way
      // to end the game. The weaver now takes wool and rope instead, which does
      // not delete that choice — it relocates it onto rope, and sharpens it,
      // because spending a finished good hurts more than spending a raw.
      final weaver = defById('weaver');
      final ropewalk = defById('ropewalk');

      expect(weaver.inputs.containsKey(Resource.rope), isTrue,
          reason: 'a sail is bolt-roped, and that is what makes rope contested');
      expect(Balance.lighthouseCost.containsKey(Resource.rope), isTrue,
          reason: 'the contest only exists because the light wants rope too');
      expect(weaver.inputs.containsKey(Resource.flax), isFalse,
          reason: 'flax feeds the ropewalk alone now');
      expect(ropewalk.inputs.containsKey(Resource.flax), isTrue);

      // And the weaver still rewards scarce labour, which is what made it
      // worth choosing over simply selling the rope.
      expect(weaver.marginPerWorkerTick,
          greaterThan(ropewalk.marginPerWorkerTick),
          reason: 'weaving must beat selling the coil it consumes');
    });

    test('every buildable has a reachable cost and sane worker cap', () {
      for (final def in kBuildingDefs) {
        expect(def.coinCost, greaterThanOrEqualTo(0));
        expect(def.maxWorkers, inInclusiveRange(0, 8));
        if (def.isProducer) expect(def.maxWorkers, greaterThan(0));
      }
    });
  });
  _spiceTests();
}

void _spiceTests() {
  group('spice', () {
    // The one thing in the game you cannot manufacture, import or buy. If any
    // of these ever becomes false, spice stops being a reason to run the dark
    // chain and becomes just another good.
    test('can only be taken, never made or bought', () {
      expect(kBuildingDefs.any((d) => d.outputs.containsKey(Resource.spice)),
          isFalse, reason: 'no shed may produce spice');
      expect(kImportables.contains(Resource.spice), isFalse,
          reason: 'an import berth must not be able to land spice');
      expect(Balance.prizeTable.containsKey(Resource.spice), isTrue,
          reason: 'a boarded hull is the only source');
      expect(Resource.spice.isContraband, isTrue);
    });

    // The player asked for this directly: holding it should draw pirates and
    // the Crown. Both fall out of these two numbers rather than any new
    // mechanic — raids scale with contrabandBaseValue (stock x basePrice) and
    // Crown attention with heatWeight.
    test('holding it is the most dangerous thing in the port', () {
      for (final r in Resource.values) {
        if (r == Resource.spice) continue;
        expect(Resource.spice.heatWeight, greaterThan(r.heatWeight),
            reason: 'spice must be the most conspicuous thing to hold, but '
                '${r.label} weighs as much or more');
        expect(Resource.spice.basePrice, greaterThan(r.basePrice),
            reason: 'raid chance scales with hoard value, so spice must be the '
                'richest target — ${r.label} is not below it');
      }
    });

    test('a hoard of spice raises raid chance above the same weight of spirits',
        () {
      final withSpice = GameState.newGame(seed: 4)..stock.add(Resource.spice, 50);
      final withSpirits =
          GameState.newGame(seed: 4)..stock.add(Resource.spirits, 50);
      expect(withSpice.contrabandBaseValue,
          greaterThan(withSpirits.contrabandBaseValue));
    });
  });
  _seedIdentityTests();
}

void _seedIdentityTests() {
  group('the run seed identifies the run', () {
    // Two reports from the SAME run carried two different "seeds" — 1702415616
    // at day 97 and 219727936 at day 126 — because the field was
    // SeededRng.seed, which is the live LCG state and advances on every draw.
    // It made one run look like two, and it could not reproduce anything,
    // which the privacy policy had been claiming it could.
    test('does not change as the run is played', () {
      final g = GameState.newGame(seed: 424242);
      expect(g.worldSeed, 424242);

      for (var i = 0; i < Balance.ticksPerDay * 30; i++) {
        g.step();
      }
      expect(g.worldSeed, 424242,
          reason: 'the world seed must not move while the run is played');
      expect(g.rng.seed, isNot(424242),
          reason: 'the live RNG state is expected to have advanced — that is '
              'exactly why it cannot be used as an identifier');
    });

    test('survives a save and load', () {
      final g = GameState.newGame(seed: 987654);
      for (var i = 0; i < Balance.ticksPerDay * 5; i++) {
        g.step();
      }
      final back = GameState.fromJson(g.toJson());
      expect(back.worldSeed, 987654);
    });

    // The claim the privacy policy makes about this field: same seed, same
    // run. The island itself is a fixed layout — Terrain is static — so what
    // the seed actually determines is the draw sequence: weather, shipping,
    // prices. Worth stating precisely, because the policy first said it laid
    // out the island, which was simply untrue.
    test('the same seed replays the same weather and shipping', () {
      List<double> draws(int seed) {
        final g = GameState.newGame(seed: seed);
        return List.generate(200, (_) => g.rng.next());
      }

      expect(draws(555), draws(555));
      expect(draws(555), isNot(draws(556)));
    });
  });
  _spiceYieldTests();
}

void _spiceYieldTests() {
  // Measured, not asserted: at 6% of a hull the full dark chain — four sheds,
  // ~1,800 coin, ~11 hands, five boardings — produced EXACTLY the same win day
  // as building none of it (126 vs 126, difficulty 4, tool/reference_runs).
  // The other 94% of a prize was raws the port already makes. If spice ever
  // drops back under a fifth of a hull, the dark trade is a trap again and
  // this says so before a tester has to.
  test('a prize is substantially spice, or boarding is not worth the powder',
      () {
    final total = Balance.prizeTable.values.fold(0, (s, v) => s + v);
    final share = Balance.prizeTable[Resource.spice]! / total;
    expect(share, greaterThanOrEqualTo(0.20),
        reason: 'spice is ${(share * 100).toStringAsFixed(0)}% of a prize; '
            'at 6% five boardings yielded ~17 spice and zero days');
  });
  _grangeTests();
}

void _grangeTests() {
  GameState husbandryPort({bool grange = true, int warehouses = 8}) {
    final g = GameState.newGame(seed: 9001);
    g.population = 60;
    g.coin = 200000;
    g.unlocked.addAll(
        ['forest_camp', 'flax_field', 'ropewalk', 'warehouse', 'grange', 'farm']);
    void add(String id) {
      for (final r in Resource.values) {
        g.stock[r] = 600;
      }
      g.build(defById(id));
    }
    add('forest_camp');
    add('flax_field');
    add('ropewalk');
    for (var i = 0; i < warehouses; i++) {
      add('warehouse');
    }
    if (grange) add('grange');
    for (var i = 0; i < g.buildings.length; i++) {
      g.setWorkers(i, g.buildings[i].def.maxWorkers);
    }
    for (final r in Resource.values) {
      g.stock[r] = 0;
    }
    g.stock[Resource.fish] = 3000;
    g.stock[Resource.grain] = 3000;
    return g;
  }

  void play(GameState g, int days) {
    for (var d = 0; d < days; d++) {
      for (var t = 0; t < Balance.ticksPerDay; t++) {
        g.step();
        g.collectAll(); // an attentive player empties the yards
      }
    }
  }

  group('the pasture', () {
    /// A port with a grown pasture and grain to feed it.
    GameState flockPort({int workers = 2, double ripe = 1.0}) {
      final g = GameState.newGame(seed: 4242);
      g.buildings.add(Building(defId: 'pasture', workers: workers));
      g.buildings.last.maturity = ripe;
      g.stock[Resource.grain] = 500;
      g.placeAll();
      return g;
    }

    test('a flock turns grain into wool and meat', () {
      final g = flockPort();
      final grainBefore = g.stock[Resource.grain];
      play(g, 4);
      expect(g.stock[Resource.wool], greaterThan(0));
      expect(g.stock[Resource.meat], greaterThan(0));
      expect(g.stock[Resource.grain], lessThan(grainBefore),
          reason: 'the feed has to actually come out of the harvest');
    });

    // THE DESIGN TARGET, and the reason Resource.nutrition exists. The flock is
    // not a food chain: the meat is there to hand back the food value the feed
    // took out, so the herd never becomes a second town competing with the
    // first for the harvest. What it earns, it earns in wool.
    test('comes out roughly even on food', () {
      final g = flockPort();
      // Only the pasture: no farm or wharf topping the stores up, and nobody
      // eating, so what moves is exactly what the flock did.
      for (final b in g.buildings) {
        if (b.defId != 'pasture') b.workers = 0;
      }
      g.population = 0;

      final before = g.foodStock;
      play(g, 20);
      final after = g.foodStock;

      // Within a fifth either way. Exact parity would be a coincidence, not a
      // design; what matters is that twenty days of keeping a flock has not
      // quietly drained or inflated the larder.
      expect(after, closeTo(before, before * 0.2),
          reason: 'fed $before person-days, left with $after — a flock must '
              'neither starve the port nor feed it');
    });

    test('is worth little the week it is fenced', () {
      final young = flockPort(ripe: 0.0);
      final grown = flockPort(ripe: 1.0);
      play(young, 3);
      play(grown, 3);
      expect(young.stock[Resource.wool], lessThan(grown.stock[Resource.wool]),
          reason: 'stock is worth nothing the week you buy it');
    });

    test('a small flock eats less than a grown one', () {
      // Feed tracks the herd, so the ramp is not a period of paying full price
      // for almost nothing — which is what would make it a trap rather than a
      // slow bet.
      double grainEaten(double ripe) {
        final g = flockPort(ripe: ripe);
        for (final b in g.buildings) {
          if (b.defId != 'pasture') b.workers = 0;
        }
        g.population = 0;
        final before = g.stock[Resource.grain];
        play(g, 5);
        return before - g.stock[Resource.grain];
      }

      expect(grainEaten(0.0), lessThan(grainEaten(1.0)));
    });

    test('an unfed flock stalls rather than starving the town', () {
      final g = flockPort();
      g.stock[Resource.grain] = 0;
      for (final b in g.buildings) {
        if (b.defId != 'pasture') b.workers = 0;
      }
      // The town still has fish. Otherwise this measures a port with no food
      // at all, which starves for reasons that have nothing to do with sheep.
      g.stock[Resource.fish] = 500;
      final popBefore = g.population;
      play(g, 3);
      expect(g.stock[Resource.grain], closeTo(0, 1e-6));
      expect(g.population, greaterThanOrEqualTo(popBefore),
          reason: 'no grain is a stalled pasture, not a dead town');
    });

    test('ripening survives a save', () {
      final g = flockPort(ripe: 0.0);
      play(g, 6);
      final before = g.buildings.firstWhere((b) => b.defId == 'pasture').maturity;
      expect(before, greaterThan(0));
      final back = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(back.buildings.firstWhere((b) => b.defId == 'pasture').maturity,
          closeTo(before, 1e-3));
    });
  });

  group('the grange', () {
    // The third route's identity: it converts TIME into goods. Trade converts
    // labour and the dark trade converts risk, and both pay out the moment you
    // act. If the grange ever pays on the day it is built it stops being a bet
    // on a long run and becomes a free upgrade everybody takes.
    test('is worth nothing the day it is built', () {
      final g = husbandryPort();
      expect(g.grangeMaturity, 0);
      expect(g.grangeYieldBonus, 1.0);
    });

    test('ripens only while it is actually worked', () {
      final worked = husbandryPort();
      play(worked, 10);
      expect(worked.grangeMaturity, greaterThan(0));

      final idle = husbandryPort();
      for (var i = 0; i < idle.buildings.length; i++) {
        if (idle.buildings[i].defId == 'grange') idle.setWorkers(i, 0);
      }
      play(idle, 40);
      expect(idle.grangeMaturity, 0,
          reason: 'hands off the grange stop the clock');
    });

    test('reaches its full worth at the advertised ramp, and stops there', () {
      final g = husbandryPort();
      play(g, Balance.grangeRipenDays.round());
      expect(g.grangeMaturity, closeTo(1.0, 0.02));
      expect(g.grangeYieldBonus, closeTo(1 + Balance.grangeMaxYield, 0.01));

      play(g, 20);
      expect(g.grangeMaturity, 1.0, reason: 'it must not grow past its cap');
      expect(g.grangeYieldBonus, closeTo(1 + Balance.grangeMaxYield, 0.001));
    });

    test('a grown grange lifts extraction by the advertised amount', () {
      final without = husbandryPort(grange: false);
      final with_ = husbandryPort();
      ripenGrange(with_, 1.0);
      play(without, 8);
      play(with_, 8);
      // Derived from the constant rather than written out, so retuning the
      // grange cannot silently leave this asserting a number the game stopped
      // believing. The 0.75 is slack: the granged port also spends two hands
      // on the grange itself, so it cannot reach the full multiplier.
      final floor = 1 + Balance.grangeMaxYield * 0.75;
      expect(with_.stock[Resource.timber],
          greaterThan(without.stock[Resource.timber] * floor),
          reason: 'a full grange must be worth most of its advertised '
              '+${(Balance.grangeMaxYield * 100).round()}% in raw timber');
    });

    // THE CORRECTION THAT MADE THIS ROUTE WORK. It lifted extractors only at
    // first, which measured as a trap — the workshops are worker-limited, not
    // input-starved, so the extra raws piled up while the grange's hands came
    // off finished goods. Median win went 100 -> 112 days: slower, while
    // working exactly as specified. If it is ever narrowed back to extractors,
    // this is the test that says so.
    test('it lifts the finished goods too, not just the raws', () {
      final without = husbandryPort(grange: false);
      final with_ = husbandryPort();
      ripenGrange(with_, 1.0);
      play(without, 8);
      play(with_, 8);
      expect(with_.stock[Resource.rope],
          greaterThan(without.stock[Resource.rope]),
          reason: 'the lighthouse asks for rope, so the route must move rope');
    });

    test('maturity survives a save', () {
      final g = husbandryPort();
      play(g, 12);
      final before = g.grangeMaturity;
      expect(before, greaterThan(0));
      final back = GameState.fromJson(g.toJson());
      expect(back.grangeMaturity, closeTo(before, 1e-9));
    });

    test('a second grange adds nothing — the bet is made once', () {
      final one = husbandryPort();
      ripenGrange(one, 1.0);
      final two = husbandryPort();
      two.unlocked.add('grange');
      for (final r in Resource.values) {
        two.stock[r] = 600;
      }
      two.build(defById('grange'));
      ripenGrange(two, 1.0);
      expect(two.grangeYieldBonus, one.grangeYieldBonus);
    });

    test('it draws hands and produces nothing itself', () {
      final def = defById('grange');
      expect(def.outputs, isEmpty);
      expect(def.maxWorkers, greaterThan(0));
      expect(def.isProducer, isTrue,
          reason: 'it takes a crew, so it is somewhere to put a hand');
    });
  });
}
