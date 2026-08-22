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

    test('ropewalk and weaver genuinely contend for flax', () {
      final ropewalk = defById('ropewalk');
      final weaver = defById('weaver');

      // Weaver wins per worker; ropewalk wins per unit of flax. Neither
      // dominates, so the right shed depends on the current bottleneck.
      expect(weaver.marginPerWorkerTick,
          greaterThan(ropewalk.marginPerWorkerTick),
          reason: 'weaver should reward scarce labour');
      expect(ropewalk.outputValuePerUnitOf(Resource.flax),
          greaterThan(weaver.outputValuePerUnitOf(Resource.flax)),
          reason: 'ropewalk should reward scarce flax');
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
}
