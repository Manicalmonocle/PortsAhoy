import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/progression.dart';
import 'package:ports_ahoy/sim/resources.dart';

void main() {
  group('the opening', () {
    test('is small enough to learn one idea at a time', () {
      final g = GameState.newGame();
      expect(g.buildings.where((b) => b.def.isProducer).length, 2,
          reason: 'two working sheds, not three');
      expect(g.population, lessThanOrEqualTo(5));
    });

    test('offers only a handful of buildings on day one', () {
      final g = GameState.newGame();
      final open = kBuildingDefs.where((d) => g.isUnlocked(d.id)).length;
      expect(open, lessThanOrEqualTo(3),
          reason: 'a catalogue of seventeen is an inventory, not a tutorial');
    });

    test('everything else is locked, with a reason given', () {
      final g = GameState.newGame();
      for (final d in kBuildingDefs) {
        if (g.isUnlocked(d.id)) continue;
        final rule = unlockRuleFor(d.id);
        expect(rule, isNotNull, reason: '${d.id} has no way to unlock');
        expect(rule!.text, isNotEmpty);
      }
    });
  });

  group('the tree', () {
    test('every building is reachable', () {
      for (final d in kBuildingDefs.where((d) => d.buildable)) {
        expect(unlockRuleFor(d.id), isNotNull, reason: d.id);
      }
    });

    test('no rule depends on a building that does not exist', () {
      final known = kBuildingDefs.map((d) => d.id).toSet();
      for (final r in kUnlockRules) {
        expect(known, contains(r.id));
        for (final need in r.requires) {
          expect(known, contains(need), reason: '${r.id} needs $need');
        }
      }
    });

    test('no rule depends on itself, directly or otherwise', () {
      Set<String> deps(String id, [Set<String>? seen]) {
        seen ??= {};
        final r = unlockRuleFor(id);
        if (r == null) return seen;
        for (final need in r.requires) {
          if (seen.add(need)) deps(need, seen);
        }
        return seen;
      }

      for (final r in kUnlockRules) {
        expect(deps(r.id), isNot(contains(r.id)), reason: r.id);
      }
    });

    test('you cannot build something you have not unlocked', () {
      final g = GameState.newGame();
      g.coin = 100000;
      for (final r in Resource.values) {
        g.stock[r] = 1000;
      }
      final smithy = defById('smithy');
      expect(g.isUnlocked('smithy'), isFalse);
      expect(g.canBuild(smithy), isFalse);
      expect(g.build(smithy), isFalse);
    });

    test('reaching a day unlocks what it should', () {
      final g = GameState.newGame();
      expect(g.isUnlocked('farm'), isFalse);
      for (var i = 0; i < 3 * Balance.ticksPerDay; i++) {
        g.step();
      }
      expect(g.isUnlocked('farm'), isTrue);
    });

    test('holding the timber unlocks the sawmill, and says so', () {
      final g = GameState.newGame();
      expect(g.isUnlocked('sawmill'), isFalse);
      g.stock[Resource.timber] = 60;
      g.checkUnlocks();
      expect(g.isUnlocked('sawmill'), isTrue);
      expect(g.logEntries.any((e) => e.text.contains('sawmill')), isTrue);
    });

    test('raising a shed reveals the next one immediately', () {
      final g = GameState.newGame();
      g.coin = 100000;
      g.stock[Resource.timber] = 200;
      g.checkUnlocks(); // sawmill
      expect(g.isUnlocked('flax_field'), isFalse);

      expect(g.build(defById('sawmill')), isTrue);
      expect(g.isUnlocked('flax_field'), isTrue,
          reason: 'the unlock should land next to the action that earned it');
      expect(g.isUnlocked('warehouse'), isTrue);
    });

    test('an unlock is sticky once earned', () {
      final g = GameState.newGame();
      g.stock[Resource.timber] = 60;
      g.checkUnlocks();
      expect(g.isUnlocked('sawmill'), isTrue);

      // Sell every stick of it; the knowledge does not go away.
      g.stock[Resource.timber] = 0;
      g.checkUnlocks();
      expect(g.isUnlocked('sawmill'), isTrue);
    });

    test('the dark trade is never unlocked early', () {
      final g = GameState.newGame();
      for (final id in ['distillery', 'bonded_cellar', 'powder_mill',
        'privateer_berth']) {
        expect(g.isUnlocked(id), isFalse, reason: id);
      }
    });

    test('the whole tree opens over a normal run', () {
      final g = GameState.newGame();
      g.coin = 500000;
      g.population = 60;
      for (var day = 0; day < 60; day++) {
        for (var i = 0; i < Balance.ticksPerDay; i++) {
          g.step();
        }
        for (final r in Resource.values) {
          g.stock[r] = 500;
        }
        // Build whatever has become available.
        for (final d in kBuildingDefs.where((d) => d.buildable)) {
          if (g.isUnlocked(d.id) && !g.buildings.any((b) => b.defId == d.id)) {
            g.build(d);
          }
        }
      }
      for (final d in kBuildingDefs.where((d) => d.buildable)) {
        expect(g.isUnlocked(d.id), isTrue, reason: '${d.id} never unlocked');
      }
    });
  });

  growthTests();
  housingArithmeticTests();
  shedGroupTests();

  group('yards', () {
    test('a warehouse makes every yard bigger', () {
      final g = GameState.newGame();
      final camp = g.buildings.first;
      final before = camp.holdCapOf(Resource.timber);

      g.unlocked.add('warehouse');
      g.coin = 100000;
      g.stock[Resource.planks] = 500;
      expect(g.build(defById('warehouse')), isTrue);
      g.syncYards();

      expect(camp.holdCapOf(Resource.timber), greaterThan(before),
          reason: '"my sheds keep filling up" needs an answer you can build');
    });

    test('a yard holds a week of work before it stalls', () {
      expect(kHoldTicks / Balance.ticksPerDay, greaterThanOrEqualTo(7));
    });

    test('the bonus survives a save', () {
      final g = GameState.newGame();
      g.unlocked.add('warehouse');
      g.coin = 100000;
      g.stock[Resource.planks] = 500;
      g.build(defById('warehouse'));

      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(restored.yardMultiplier, g.yardMultiplier);
      expect(restored.buildings.first.yardBonus, g.yardMultiplier);
    });
  });

  group('saves', () {
    test('unlocks round-trip', () {
      final g = GameState.newGame();
      g.stock[Resource.timber] = 60;
      g.checkUnlocks();

      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(restored.unlocked, g.unlocked);
    });

    test('a save from before the tree keeps everything it had', () {
      final g = GameState.newGame();
      final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
      json.remove('unlocked');
      final restored = GameState.fromJson(json);
      // Taking buildings away from an established port would be nonsense.
      for (final d in kBuildingDefs) {
        expect(restored.isUnlocked(d.id), isTrue, reason: d.id);
      }
    });
  });
}

// ---------------------------------------------------------------------------

void growthTests() {
  group('town growth', () {
    /// Run a well-fed, solvent port for [days] and return where it settled.
    int settle(GameState g, {int days = 400}) {
      for (var d = 0; d < days; d++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          g.step();
        }
        g.stock[Resource.fish] = 400;
        g.stock[Resource.grain] = 400;
        g.coin = 99999;
      }
      return g.population;
    }

    test('a fed town fills every roof exactly — no off-by-one', () {
      for (final cottages in [0, 1, 2, 4]) {
        final g = GameState.newGame();
        for (var i = 0; i < cottages; i++) {
          g.buildings.add(Building(defId: 'house'));
        }
        g.placeAll();
        expect(settle(g), g.housingCapacity,
            reason: 'with ${cottages + 1} cottages');
      }
    });

    test('a hungry town stalls short of its roofs — and says so', () {
      final g = GameState.newGame();
      g.buildings.add(Building(defId: 'house'));
      g.placeAll();
      // Keep food on a knife edge: enough to eat, never enough to grow on.
      for (var d = 0; d < 60; d++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          g.step();
        }
        g.coin = 99999;
        for (final r in Resource.values.where((r) => r.isFood)) {
          g.stock[r] = 0;
        }
        g.stock[Resource.fish] = g.population * 1.2;
      }
      expect(g.population, lessThan(g.housingCapacity));
      expect(g.growthBlocker, isNotNull,
          reason: 'the player must be told why the town stopped growing');
      expect(g.growthBlocker, contains('food'));
    });

    test('a full town says the roofs are the reason', () {
      final g = GameState.newGame();
      g.buildings.add(Building(defId: 'house'));
      g.placeAll();
      settle(g);
      expect(g.population, g.housingCapacity);
      expect(g.growthBlocker, contains('roof'));
    });

    test('an unpayable payroll is named as the reason', () {
      // The case that prompted this: 9/15 population, plenty of roofs, and no
      // visible reason. Unpaid hands leave, which cancels the growth roll and
      // leaves the town apparently stuck.
      final g = GameState.newGame();
      g.buildings.add(Building(defId: 'house'));
      g.buildings.add(Building(defId: 'house'));
      g.placeAll();
      g.stock[Resource.fish] = 400;
      g.coin = 0;

      expect(g.population, lessThan(g.housingCapacity));
      expect(g.growthIsStalled, isTrue);
      expect(g.growthBlocker, contains('payroll'));
    });

    test('a full town is not reported as stalled — it is just full', () {
      final g = GameState.newGame();
      g.placeAll();
      g.coin = 99999;
      g.stock[Resource.fish] = 400;
      g.population = g.housingCapacity;
      expect(g.growthBlocker, contains('roof'));
      expect(g.growthIsStalled, isFalse,
          reason: 'a full town needs a cottage, not a warning');
    });

    test('a healthy town says it is growing rather than saying nothing', () {
      // Reported as "all three are met" with no idea whether anything was
      // happening. Growth is a coin flip per day, so silence reads exactly
      // like being stuck.
      final g = GameState.newGame();
      g.buildings.add(Building(defId: 'house'));
      g.placeAll();
      g.stock[Resource.fish] = 400;
      g.coin = 99999;

      expect(g.isGrowing, isTrue);
      expect(g.growthStatus, contains('growing'));
      expect(g.growthStatus, contains('roof'),
          reason: 'say how much room is left, so progress is legible');
    });

    test('an arrival is announced on the tick it happens', () {
      final g = GameState.newGame();
      g.buildings.add(Building(defId: 'house'));
      g.placeAll();
      var sawArrival = false;
      for (var d = 0; d < 30 && !sawArrival; d++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          g.step();
          if (g.arrivalsThisTick > 0) sawArrival = true;
        }
        g.stock[Resource.fish] = 400;
        g.coin = 99999;
      }
      expect(sawArrival, isTrue,
          reason: 'the UI needs a moment to flash on');
    });

    test('the arrival flag clears again', () {
      final g = GameState.newGame();
      g.buildings.add(Building(defId: 'house'));
      g.placeAll();
      g.stock[Resource.fish] = 400;
      g.coin = 99999;
      for (var d = 0; d < 40; d++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          g.step();
          // Never sticky: an arrival lasts exactly one tick.
          if (g.arrivalsThisTick > 0) {
            g.step();
            expect(g.arrivalsThisTick, 0);
            return;
          }
        }
      }
    });

    test('a growing town reports nothing blocking it', () {
      final g = GameState.newGame();
      g.buildings.add(Building(defId: 'house'));
      g.placeAll();
      g.stock[Resource.fish] = 400;
      g.coin = 99999;
      expect(g.population, lessThan(g.housingCapacity));
      expect(g.growthBlocker, isNull);
      expect(g.growthIsStalled, isFalse);
    });
  });
}

// ---------------------------------------------------------------------------

void shedGroupTests() {
  group('working a trade as a group', () {
    GameState portWith(String defId, int count) {
      final g = GameState.newGame();
      g.population = 60;
      g.unlocked.add(defId);
      for (var i = 0; i < count; i++) {
        g.coin = 100000;
        for (final r in Resource.values) {
          g.stock[r] = 500;
        }
        g.build(defById(defId));
      }
      return g;
    }

    test('adding a hand fills the emptiest shed first', () {
      final g = portWith('forest_camp', 3);
      // newGame already ships one forest camp, so read the real count.
      final sheds = g.shedsOfType('forest_camp');
      for (final b in sheds) {
        b.workers = 0;
      }
      // One add per shed should land one each, not all on the first.
      for (var i = 0; i < sheds.length; i++) {
        expect(g.addWorkerTo('forest_camp'), isTrue);
      }
      expect(sheds.map((b) => b.workers).toList(),
          List.filled(sheds.length, 1));
    });

    test('removing a hand takes it off the fullest shed', () {
      final g = portWith('forest_camp', 2);
      final sheds = g.shedsOfType('forest_camp');
      sheds[0].workers = 3;
      sheds[1].workers = 1;
      expect(g.removeWorkerFrom('forest_camp'), isTrue);
      expect(sheds[0].workers, 2);
      expect(sheds[1].workers, 1);
    });

    test('a group never takes more hands than the town has', () {
      final g = portWith('forest_camp', 4);
      for (final b in g.buildings) {
        b.workers = 0;
      }
      g.population = 3;
      var added = 0;
      while (g.addWorkerTo('forest_camp')) {
        added++;
      }
      expect(added, 3);
      expect(g.assignedWorkers, lessThanOrEqualTo(g.population));
    });

    test('a group never exceeds its own maximum', () {
      final g = portWith('forest_camp', 2);
      for (final b in g.buildings) {
        b.workers = 0;
      }
      final max =
          defById('forest_camp').maxWorkers * g.shedsOfType('forest_camp').length;
      var added = 0;
      while (g.addWorkerTo('forest_camp')) {
        added++;
      }
      expect(added, max);
      expect(g.addWorkerTo('forest_camp'), isFalse);
    });

    test('removing from an empty trade changes nothing', () {
      final g = portWith('forest_camp', 1);
      for (final b in g.buildings) {
        b.workers = 0;
      }
      expect(g.removeWorkerFrom('forest_camp'), isFalse);
      expect(g.assignedWorkers, 0);
    });

    test('the panel lists trades, not sheds, and skips the cottages', () {
      final g = portWith('forest_camp', 4);
      g.unlocked.add('house');
      for (var i = 0; i < 3; i++) {
        g.coin = 100000;
        g.stock[Resource.planks] = 500;
        g.build(defById('house'));
      }

      final types = g.staffableTypes;
      expect(types.toSet().length, types.length, reason: 'no duplicate trades');
      expect(types, contains('forest_camp'));
      expect(types, isNot(contains('house')),
          reason: 'a cottage has nothing to assign, so it is just clutter');
      expect(types.length, lessThan(g.buildings.length),
          reason: 'the whole point is fewer rows than sheds');
    });

    test('the order is stable as the port grows', () {
      final g = portWith('forest_camp', 2);
      final before = g.staffableTypes;
      g.unlocked.add('sawmill');
      g.coin = 100000;
      g.stock[Resource.timber] = 500;
      g.build(defById('sawmill'));
      // Existing entries keep their places; the new trade joins the list.
      expect(g.staffableTypes.where(before.contains).toList(), before);
    });
  });
}

// ---------------------------------------------------------------------------

void housingArithmeticTests() {
  group('housing arithmetic', () {
    test('every roof is worth the same, so the totals are predictable', () {
      // Reported as "cottage says it houses 5 but population is always one
      // less". The cause was a base of 4 against a cottage of 5, so capacity
      // landed on 9, 14, 49 where a player predicts 10, 15, 50.
      expect(Balance.baseHousing, defById('house').housing,
          reason: 'a mismatched base reads as an off-by-one to every player');
    });

    test('capacity is exactly five times the roofs', () {
      final g = GameState.newGame();
      for (var i = 0; i < 6; i++) {
        expect(g.housingCapacity, 5 * (g.cottageCount + 1),
            reason: 'with ${g.cottageCount} cottages');
        g.coin = 100000;
        g.stock[Resource.planks] = 500;
        g.build(defById('house'));
      }
    });

    test('the breakdown adds up to the number shown', () {
      final g = GameState.newGame();
      g.coin = 100000;
      g.stock[Resource.planks] = 500;
      g.build(defById('house'));
      expect(g.housingBreakdown, contains('${g.housingCapacity}'));
      expect(g.housingBreakdown, contains('${g.cottageCount}'));
    });
  });
  _darkTradeReachability();
}

void _darkTradeReachability() {
  group('the dark trade is reachable', () {
    // THE BUG THIS EXISTS TO STOP COMING BACK.
    //
    // Every dark shed used to unlock only once the previous dark shed had been
    // BUILT. Measured against a complete human run — 93 days, lighthouse lit —
    // the Bonded Cellar and the Privateer Berth never became available at all,
    // because the player never built the shed each was hiding behind. A player
    // reporting "the dark trade is too late to matter" was describing a
    // subsystem that was not late but absent.
    test('no dark shed hides behind another dark shed', () {
      for (final id in kDarkBuildingIds) {
        final rule = unlockRuleFor(id);
        expect(rule, isNotNull, reason: '$id has no unlock rule');
        for (final needed in rule!.requires) {
          expect(kDarkBuildingIds.contains(needed), isFalse,
              reason: '$id only appears once you have built $needed, which is '
                  'itself part of the dark trade. That chain made half the '
                  'subsystem unreachable in a winning run.');
        }
      }
    });

    // Concealment has to be buyable BEFORE contraband exists, or a first dark
    // run is forced to get exposed before it can do anything about it.
    test('concealment does not wait on producing contraband', () {
      final cellar = unlockRuleFor('bonded_cellar')!;
      expect(cellar.requires, isNot(contains('distillery')));
      expect(cellar.requires, isNot(contains('powder_mill')));
    });

    // Replays the real build days from tool/reference_runs: warehouse 36,
    // smithy 51, won 93. Both must land with real runway left, not at the death.
    test('both late sheds open with most of a real run still to play', () {
      const builtOn = {'warehouse': 36, 'smithy': 51, 'mine': 22, 'ropewalk': 17};
      const wonOn = 93;

      for (final id in ['bonded_cellar', 'privateer_berth']) {
        final rule = unlockRuleFor(id)!;
        var opensOn = rule.minDay;
        for (final needed in rule.requires) {
          final day = builtOn[needed];
          expect(day, isNotNull,
              reason: '$id now waits on $needed, which that run never built — '
                  'it would be unreachable again');
          opensOn = opensOn > day! ? opensOn : day;
        }
        expect(opensOn, lessThan(wonOn - 30),
            reason: '$id opens on day $opensOn of a run won on $wonOn — under '
                'a month of runway is what "too late to matter" felt like');
      }
    });
  });
}
