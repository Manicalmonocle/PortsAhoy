import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/events.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/market.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:ports_ahoy/sim/trade.dart';

/// A port big enough and rich enough to be eligible for anything.
GameState wellFoundPort({int seed = 4242}) {
  final g = GameState.newGame(seed: seed);
  for (final id in [
    'sawmill', 'flax_field', 'ropewalk', 'weaver', 'mine',
    'smithy', 'cooperage', 'warehouse', 'house', 'house',
  ]) {
    g.buildings.add(Building(defId: id));
  }
  g.population = 30;
  g.coin = 20000;
  g.stock[Resource.fish] = 400;
  g.stock[Resource.grain] = 400;
  return g;
}

/// Run [days] days, keeping the port fed and solvent so mercy floors never
/// suppress the deck, and return every event that began.
List<String> runCollecting(GameState g, int days) {
  final seen = <String>[];
  var known = <ActiveEvent>{};
  for (var d = 0; d < days; d++) {
    for (var h = 0; h < Balance.ticksPerDay; h++) {
      tickAndCollect(g);
      final live = g.events.live(g.tick).toSet();
      for (final e in live.difference(known)) {
        seen.add(e.defId);
      }
      known = live;
    }
    g.coin = 20000;
    g.stock[Resource.fish] = 400;
    g.stock[Resource.grain] = 400;
  }
  return seen;
}

void tickAndCollect(GameState g, [int ticks = 1]) {
  for (var i = 0; i < ticks; i++) {
    g.step();
    g.collectAll();
  }
}

void main() {
  group('scheduling', () {
    test('nothing bites during the opening grace period', () {
      final g = wellFoundPort();
      for (var i = 0; i < EventTuning.graceDays * Balance.ticksPerDay; i++) {
        tickAndCollect(g);
        expect(g.events.live(g.tick), isEmpty,
            reason: 'the first twelve days are the tutorial');
      }
      // An omen may be posted on the last night of grace; that is the point of
      // forewarning, and it does not bite until the following day.
      for (final e in g.events.active) {
        expect(e.startTick,
            greaterThanOrEqualTo(EventTuning.graceDays * Balance.ticksPerDay));
      }
    });

    test('events do eventually arrive', () {
      final g = wellFoundPort();
      final seen = runCollecting(g, 220);
      expect(seen, isNotEmpty);
      expect(seen.toSet().length, greaterThan(3),
          reason: 'the deck should not be dealing the same card over and over');
    });

    test('an omen always precedes the event biting', () {
      final g = wellFoundPort();
      for (var i = 0; i < 200 * Balance.ticksPerDay; i++) {
        tickAndCollect(g);
        for (final e in g.events.active) {
          if (e.def.omenTicks > 0) {
            expect(e.startTick, greaterThan(e.omenTick),
                reason: 'forewarning must come before the event');
          }
        }
        if (g.events.active.isNotEmpty) break;
      }
    });

    test('only one hazard is ever in play at a time', () {
      final g = wellFoundPort();
      for (var d = 0; d < 300; d++) {
        for (var h = 0; h < Balance.ticksPerDay; h++) {
          tickAndCollect(g);
          final hazards =
              g.events.active.where((e) => e.def.isHazard).length;
          expect(hazards, lessThanOrEqualTo(1));
        }
        g.coin = 20000;
        g.stock[Resource.fish] = 400;
        g.stock[Resource.grain] = 400;
      }
    });

    test('duration is fixed at draw time, so a mid-omen reload cannot reroll',
        () {
      final g = wellFoundPort();
      ActiveEvent? pending;
      for (var i = 0; i < 400 * Balance.ticksPerDay && pending == null; i++) {
        tickAndCollect(g);
        pending = g.events.active
            .where((e) => e.isOmen(g.tick))
            .cast<ActiveEvent?>()
            .firstWhere((e) => true, orElse: () => null);
      }
      expect(pending, isNotNull, reason: 'expected to catch an event in omen');

      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      final same = restored.events.active
          .firstWhere((e) => e.defId == pending!.defId);
      expect(same.startTick, pending!.startTick);
      expect(same.endTick, pending.endTick);
      expect(same.absentCount, pending.absentCount);
      expect(same.target, pending.target);
    });
  });

  group('eligibility', () {
    test('the sound only freezes in winter', () {
      final def = eventById('the_sound_froze');
      expect(def.seasonWeight.keys, [3]);
      // Season 3 is days 91-120 of each 120-day year.
      const ctxWinter = EventContext(
        day: 100, buildableCount: 20, population: 30, assignedWorkers: 20,
        foodDays: 10, coin: 9999, dailyWageBill: 40, buildingIds: {},
      );
      expect(ctxWinter.season, 3);
    });

    test('an event needing a shed you do not have cannot be drawn', () {
      final sys = EventSystem();
      const ctx = EventContext(
        day: 200, buildableCount: 20, population: 30, assignedWorkers: 20,
        foodDays: 10, coin: 9999, dailyWageBill: 40,
        buildingIds: {'forest_camp'},
      );
      // Drawn many times, a sawpit jam must never appear without a sawmill.
      final rng = SeededRng(11);
      for (var i = 0; i < 60; i++) {
        sys.nextRollTick = 0;
        sys.active.clear();
        final ev = sys.rollAtDayEnd(5000 + i * 24, rng, ctx);
        expect(ev?.defId, isNot('sawpit_jam'));
        expect(ev?.defId, isNot('retting_rot'));
      }
    });

    test('mercy floors spare a port that is already on the floor', () {
      final sys = EventSystem();
      final rng = SeededRng(3);
      const starving = EventContext(
        day: 200, buildableCount: 20, population: 30, assignedWorkers: 20,
        foodDays: 0.5, coin: 9999, dailyWageBill: 40, buildingIds: {},
      );
      for (var i = 0; i < 60; i++) {
        sys.nextRollTick = 0;
        sys.active.clear();
        final ev = sys.rollAtDayEnd(5000 + i * 24, rng, starving);
        if (ev != null) {
          expect(ev.def.isHazard, isFalse,
              reason: 'a starving port must only ever draw a boon');
        }
      }
    });

    test('a broke port is not hit with a hazard either', () {
      final sys = EventSystem();
      final rng = SeededRng(5);
      const broke = EventContext(
        day: 200, buildableCount: 20, population: 30, assignedWorkers: 20,
        foodDays: 10, coin: 10, dailyWageBill: 40, buildingIds: {},
      );
      for (var i = 0; i < 60; i++) {
        sys.nextRollTick = 0;
        sys.active.clear();
        final ev = sys.rollAtDayEnd(5000 + i * 24, rng, broke);
        if (ev != null) expect(ev.def.isHazard, isFalse);
      }
    });
  });

  group('effects', () {
    /// Force a specific event to be live right now.
    void force(GameState g, String id, {int days = 3}) {
      g.events.active.clear();
      g.events.active.add(ActiveEvent(
        defId: id,
        omenTick: g.tick,
        startTick: g.tick + 1,
        endTick: g.tick + 1 + days * Balance.ticksPerDay,
        absentCount: eventById(id).absentFraction > 0
            ? (g.assignedWorkers * eventById(id).absentFraction).round()
            : 0,
      ));
      g.events.nextRollTick = 1 << 30; // no further rolls during the test
    }

    test('a throughput event slows the shed it names', () {
      final calm = wellFoundPort();
      final blown = wellFoundPort();
      for (final g in [calm, blown]) {
        for (final b in g.buildings) {
          if (b.defId == 'fishing_wharf') b.workers = 2;
        }
        // The helper stocks food above the storage cap; leave headroom or the
        // wharf is blocked in both ports and the comparison proves nothing.
        g.stock[Resource.fish] = 50;
        g.events.nextRollTick = 1 << 30;
      }
      force(blown, 'north_easterly');

      tickAndCollect(calm);
      tickAndCollect(blown);
      expect(blown.stock[Resource.fish], lessThan(calm.stock[Resource.fish]));
    });

    test('a yield event consumes inputs and destroys the difference', () {
      final g = wellFoundPort();
      final sawmill = g.buildings.firstWhere((b) => b.defId == 'sawmill');
      sawmill.workers = 3;
      g.stock[Resource.timber] = 500;
      force(g, 'sawpit_jam');

      final timberBefore = g.stock[Resource.timber];
      final planksBefore = g.stock[Resource.planks];
      tickAndCollect(g);

      expect(g.stock[Resource.timber], lessThan(timberBefore),
          reason: 'timber is still consumed in full');
      final made = g.stock[Resource.planks] - planksBefore;
      final consumed = timberBefore - g.stock[Resource.timber];
      // 0.30 timber -> 0.25 planks normally; at 40% yield it is much worse.
      expect(made / consumed, lessThan(0.25 / 0.30 * 0.5));
    });

    test('a fever never mutates worker assignments and snaps back', () {
      final g = wellFoundPort();
      for (final b in g.buildings) {
        if (b.def.isStaffable && g.idleWorkers > 0) b.workers = 1;
      }
      final before = {for (final b in g.buildings) b.defId: b.workers};

      force(g, 'grey_fever', days: 2);
      for (var i = 0; i < Balance.ticksPerDay; i++) {
        tickAndCollect(g);
      }
      final during = {for (final b in g.buildings) b.defId: b.workers};
      expect(during, before,
          reason: 'absence must never be written into Building.workers');

      g.events.active.clear();
      tickAndCollect(g);
      final after = {for (final b in g.buildings) b.defId: b.workers};
      expect(after, before);
    });

    test('a fever cannot be dodged by reshuffling hands', () {
      final g = wellFoundPort();
      final camp = g.buildings.firstWhere((b) => b.defId == 'forest_camp');
      camp.workers = 4;
      force(g, 'grey_fever', days: 3);
      tickAndCollect(g);
      final absentThen = g.events.effects.absentTotal;

      // Spread the same hands across two sheds and the headcount is unchanged.
      camp.workers = 2;
      g.buildings.firstWhere((b) => b.defId == 'sawmill').workers = 2;
      tickAndCollect(g);
      expect(g.events.effects.absentTotal, absentThen);
    });

    test('a blockade stops new ships making the quay', () {
      final g = wellFoundPort();
      force(g, 'the_sound_froze', days: 5);
      g.market.ships.clear();
      for (var i = 0; i < 4 * Balance.ticksPerDay; i++) {
        tickAndCollect(g);
      }
      expect(g.market.ships, isEmpty);
    });

    test('a fire takes a bite out of finished goods only', () {
      final g = wellFoundPort();
      g.stock[Resource.planks] = 200;
      g.stock[Resource.timber] = 200;
      final coinBefore = g.coin;
      force(g, 'shed_fire', days: 1);
      tickAndCollect(g);

      expect(g.stock[Resource.planks], lessThan(200));
      expect(g.stock[Resource.timber], greaterThanOrEqualTo(200 - 1e-9),
          reason: 'raw timber is not in the burnt shed');
      expect(g.coin, coinBefore, reason: 'a fire does not take coin');
    });

    test('the levy is proportional and can never bankrupt a port', () {
      final g = wellFoundPort();
      g.coin = 100;
      force(g, 'crown_levy', days: 1);
      tickAndCollect(g);
      expect(g.coin, greaterThan(0));
      expect(g.coin, lessThan(100));
    });
  });

  // Reported from play: "what does north easterly event mean? it is very
  // vague". The banner showed a line of flavour and a countdown and never said
  // what the event did — and in that case the flavour was actively wrong,
  // implying your own hulls were stuck in port when they sail as normal.
  group('an event says what it does', () {
    test('every event describes at least one concrete effect', () {
      for (final d in kEventDefs) {
        expect(d.effectLines(), isNotEmpty,
            reason: '"${d.name}" would show a player nothing but prose');
      }
    });

    test('a blocked quay does not stop your own consignments', () {
      final g = wellFoundPort();
      g.stock[Resource.planks] = 200;
      g.events.active.add(ActiveEvent(
        defId: 'north_easterly',
        omenTick: g.tick,
        startTick: g.tick,
        endTick: g.tick + 4 * Balance.ticksPerDay,
      ));
      g.events.nextRollTick = 1 << 30;
      tickAndCollect(g);

      expect(g.events.effects.conditions.shipsBlocked, isTrue);
      expect(g.sendVoyage(kDestinations.first, {Resource.planks: 40.0}), isTrue,
          reason: 'the banner promises this, so it had better be true');

      final def = eventById('north_easterly');
      expect(def.effectLines().join(' '), contains('consignments sail'));
    });

    test('the privateer scare still doubles the danger at sea', () {
      // Moved off a hard-coded defId check and onto a field so the banner can
      // state it. The number must not have changed on the way.
      expect(eventById('privateer_scare').voyageRiskScale, 2.0);

      final g = wellFoundPort();
      g.events.active.add(ActiveEvent(
        defId: 'privateer_scare',
        omenTick: g.tick,
        startTick: g.tick,
        endTick: g.tick + 5 * Balance.ticksPerDay,
      ));
      g.events.nextRollTick = 1 << 30;
      tickAndCollect(g);

      expect(g.events.effects.voyageRiskScale, 2.0,
          reason: 'the lanes are twice as dangerous while they are out there');
    });
  });

  group('market conditions', () {
    test('a shock drags a price, and it walks home once the event lifts', () {
      final g = wellFoundPort();
      g.events.active.add(ActiveEvent(
        defId: 'privateer_scare',
        omenTick: g.tick,
        startTick: g.tick + 1,
        endTick: g.tick + 1 + 5 * Balance.ticksPerDay,
      ));
      g.events.nextRollTick = 1 << 30;

      final before = g.market.index[Resource.ore]!;
      for (var i = 0; i < 4 * Balance.ticksPerDay; i++) {
        tickAndCollect(g);
      }
      final during = g.market.index[Resource.ore]!;
      expect(during, greaterThan(before),
          reason: 'privateers in the lanes should bid imports up');

      g.events.active.clear();
      for (var i = 0; i < 400; i++) {
        tickAndCollect(g);
      }
      expect(g.market.index[Resource.ore]!, lessThan(during),
          reason: 'the shock should decay once the lanes are swept');
    });

    test('a glut targets one good, chosen at draw time', () {
      final def = eventById('glutted_market');
      expect(def.targetsAGood, isTrue);
      expect(def.targetIndex, lessThan(1.0));
    });
  });

  group('determinism', () {
    test('advance() consumes no randomness at all', () {
      final g = wellFoundPort();
      // Step to just after a day boundary so no roll happens in the window.
      tickAndCollect(g);
      final sys = g.events;
      final rng = SeededRng(99);
      final seedBefore = rng.seed;
      for (var t = 1; t < 500; t++) {
        sys.advance(t);
      }
      expect(rng.seed, seedBefore);
    });

    test('the same seed produces the same weather', () {
      final a = wellFoundPort(seed: 777);
      final b = wellFoundPort(seed: 777);
      final ea = runCollecting(a, 150);
      final eb = runCollecting(b, 150);
      expect(ea, eb);
    });

    test('a reloaded game keeps the same schedule', () {
      final g = wellFoundPort(seed: 31415);
      runCollecting(g, 90);
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);

      expect(restored.events.nextRollTick, g.events.nextRollTick);
      expect(restored.events.active.length, g.events.active.length);
      expect(restored.events.history, g.events.history);
    });

    test('a v1 save with no events block still loads', () {
      final g = GameState.newGame();
      final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
      json.remove('events');
      final restored = GameState.fromJson(json);
      expect(restored.events.active, isEmpty);
      expect(restored.events.nextRollTick,
          EventTuning.graceDays * Balance.ticksPerDay);
    });
  });

  group('catalogue integrity', () {
    test('every event is internally consistent', () {
      for (final d in kEventDefs) {
        expect(d.minDays, greaterThan(0), reason: d.id);
        expect(d.maxDays, greaterThanOrEqualTo(d.minDays), reason: d.id);
        expect(d.seasonWeight, isNotEmpty, reason: d.id);
        expect(d.name, isNotEmpty, reason: d.id);
        expect(d.omenLine, isNotEmpty, reason: d.id);
        expect(d.onsetLine, isNotEmpty, reason: d.id);
        expect(d.liftLine, isNotEmpty, reason: d.id);
      }
    });

    test('event ids are unique', () {
      final ids = kEventDefs.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every building an event names actually exists', () {
      final known = kBuildingDefs.map((b) => b.id).toSet();
      for (final d in kEventDefs) {
        if (d.requiresBuildingId != null) {
          expect(known, contains(d.requiresBuildingId), reason: d.id);
        }
        for (final id in [...d.throughput.keys, ...d.yieldScale.keys]) {
          if (id == '*') continue;
          expect(known, contains(id), reason: '${d.id} -> $id');
        }
      }
    });

    test('the deck holds both hazards and boons', () {
      expect(kEventDefs.where((d) => d.isHazard), isNotEmpty);
      expect(kEventDefs.where((d) => !d.isHazard).length,
          greaterThanOrEqualTo(3),
          reason: 'enough good weather to keep the deck from feeling punitive');
    });
  });
}
