import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/market.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:ports_ahoy/sim/retinue.dart';
import 'package:ports_ahoy/sim/trade.dart';

GameState stocked() {
  final g = GameState.newGame();
  g.coin = 20000;
  // Warehouses first: without the headroom the stores below sit at the cap and
  // there is nowhere to buy into.
  g.buildings.add(Building(defId: 'warehouse'));
  g.buildings.add(Building(defId: 'warehouse'));
  g.placeAll();
  g.stock[Resource.rope] = 300;
  g.stock[Resource.tools] = 200;
  g.stock[Resource.timber] = 120;
  return g;
}

void main() {
  group('the chandler', () {
    test('buys exactly what you asked for, right now', () {
      final g = stocked();
      final before = g.stock[Resource.timber];
      final coinBefore = g.coin;

      final spent = g.buyFromChandler(Resource.timber, 50);

      expect(spent, greaterThan(0));
      expect(g.stock[Resource.timber], closeTo(before + 50, 1e-6),
          reason: 'no waiting and no hoping a ship carries it');
      expect(g.coin, lessThan(coinBefore));
    });

    test('it is dearer than an import berth — that is the premium for now', () {
      expect(Balance.chandlerMarkup, greaterThan(Balance.importMargin));
    });

    test('it will not sell a finished good at any price', () {
      final g = stocked();
      for (final r in [
        Resource.planks,
        Resource.rope,
        Resource.barrels,
        Resource.sailcloth,
        Resource.tools,
      ]) {
        expect(Balance.chandlerStock.contains(r), isFalse, reason: r.label);
        expect(g.buyFromChandler(r, 50), 0);
      }
    });

    test('every leg of the win condition still comes from your own sheds', () {
      for (final r in Balance.lighthouseCost.keys) {
        expect(Balance.chandlerStock.contains(r), isFalse, reason: r.label);
      }
    });

    test('it is capped by coin and never overdraws', () {
      final g = stocked();
      g.coin = 20;
      // A thin purse buys a little, not nothing and never more than it has.
      final spent = g.buyFromChandler(Resource.timber, 500);
      expect(spent, lessThanOrEqualTo(20));
      expect(g.coin, greaterThanOrEqualTo(0));
    });

    test('it is capped by shed room', () {
      final g = stocked();
      g.coin = 100000;
      g.stock[Resource.ore] = g.storageCapacity;
      expect(g.buyFromChandler(Resource.ore, 500), 0);
      expect(g.stock[Resource.ore],
          lessThanOrEqualTo(g.storageCapacity + 1e-6));
    });

    test('buying in bulk pushes the price up against you', () {
      final g = stocked();
      g.coin = 200000;
      final before = g.market.index[Resource.ore]!;
      g.buyFromChandler(Resource.ore, 150);
      expect(g.market.index[Resource.ore]!, greaterThan(before));
    });
  });

  group('voyages', () {
    final ostmark = destinationById('ostmark');

    test('sending loads the cargo out of the stores', () {
      final g = stocked();
      final before = g.stock[Resource.rope];

      expect(g.sendVoyage(ostmark, {Resource.rope: 100}), isTrue);

      expect(g.stock[Resource.rope], closeTo(before - 100, 1e-6));
      expect(g.voyages, hasLength(1));
      expect(g.voyages.first.quotedCoin, greaterThan(0));
    });

    test('it never touches the local price — that is the whole point', () {
      final g = stocked();
      final before = g.market.index[Resource.rope]!;
      g.sendVoyage(ostmark, {Resource.rope: 200});
      expect(g.market.index[Resource.rope], before,
          reason: 'selling abroad is how you move volume without '
              'collapsing your own quay');
    });

    test('a port that wants your cargo pays more than one that does not', () {
      final g = stocked();
      final wantsRope = g.quoteVoyage(ostmark, {Resource.rope: 100});
      final wantsTools =
          g.quoteVoyage(destinationById('greyhaven'), {Resource.rope: 100});
      expect(wantsRope, greaterThan(wantsTools));
    });

    test('the far port pays best and takes longest', () {
      final g = stocked();
      final near = g.quoteVoyage(ostmark, {Resource.tools: 100});
      final far =
          g.quoteVoyage(destinationById('the_reaches'), {Resource.tools: 100});
      expect(far, greaterThan(near));
      expect(destinationById('the_reaches').days, greaterThan(ostmark.days));
      expect(destinationById('the_reaches').risk, greaterThan(ostmark.risk));
    });

    test('a quote is fixed at departure, so the payoff is known', () {
      final g = stocked();
      g.sendVoyage(ostmark, {Resource.rope: 100});
      final quoted = g.voyages.first.quotedCoin;

      // Collapse the local price. The consignment was sold at departure and
      // must be completely unaffected by what happens on your own quay.
      g.market.index[Resource.rope] = 0.45;
      for (var i = 0; i < ostmark.days * Balance.ticksPerDay - 4; i++) {
        g.step();
        expect(g.voyages.first.quotedCoin, quoted);
      }
    });

    test('it returns on time and pays out', () {
      // Ostmark's risk is low; over several runs at least one must pay.
      // Coin also moves for wages over a three-day crossing, so read the
      // outcome off the log rather than off the treasury.
      var paid = false;
      for (var seed = 0; seed < 12 && !paid; seed++) {
        final g = GameState.newGame(seed: 100 + seed);
        g.stock[Resource.rope] = 200;
        g.sendVoyage(ostmark, {Resource.rope: 100});
        for (var i = 0; i < ostmark.days * Balance.ticksPerDay + 2; i++) {
          g.step();
        }
        expect(g.voyages, isEmpty, reason: 'she is due back by now');
        paid = g.logEntries.any((e) => e.text.contains('paid out'));
      }
      expect(paid, isTrue);
    });

    test('nothing anywhere shortens a crossing', () {
      final g = stocked();
      g.sendVoyage(ostmark, {Resource.rope: 50});
      final due = g.voyages.first.returnTick;

      // A fortune changes nothing about when she is due.
      g.coin = 10000000;
      for (var i = 0; i < 10; i++) {
        g.step();
      }
      expect(g.voyages.first.returnTick, due);
    });

    test('the local quay is always open, so a voyage is never a gate', () {
      final g = stocked();
      g.sendVoyage(ostmark, {Resource.rope: 100});
      // Everything else still works while she is out.
      expect(g.stock[Resource.rope], greaterThan(0));
      expect(g.canSendVoyage, isTrue);
      expect(g.buyFromChandler(Resource.timber, 10), greaterThan(0));
    });

    test('you cannot send cargo you do not have at all', () {
      final g = stocked();
      g.stock[Resource.sailcloth] = 0;
      expect(g.sendVoyage(ostmark, {Resource.sailcloth: 500}), isFalse);
      expect(g.voyages, isEmpty);
    });

    test('a hold is trimmed to what the stores still hold, not refused', () {
      // The reported bug: load the hold, a workshop eats some of it, press
      // send, and the whole consignment was silently rejected while the panel
      // cleared as though it had sailed.
      final g = stocked();
      g.stock[Resource.rope] = 40;

      expect(g.sendVoyage(ostmark, {Resource.rope: 100}), isTrue,
          reason: 'she should sail with what is actually there');
      expect(g.voyages.first.cargo[Resource.rope], closeTo(40, 1e-9));
      expect(g.stock[Resource.rope], closeTo(0, 1e-9));
    });

    test('a partly-eaten hold still sails with the rest', () {
      final g = stocked();
      g.stock[Resource.rope] = 60;
      g.stock[Resource.tools] = 5;

      expect(
          g.sendVoyage(ostmark, {Resource.rope: 60, Resource.tools: 50}),
          isTrue);
      final cargo = g.voyages.first.cargo;
      expect(cargo[Resource.rope], closeTo(60, 1e-9));
      expect(cargo[Resource.tools], closeTo(5, 1e-9));
      expect(g.stock[Resource.rope], closeTo(0, 1e-9));
      expect(g.stock[Resource.tools], closeTo(0, 1e-9));
    });

    test('the quote matches the cargo that actually sailed', () {
      final g = stocked();
      g.stock[Resource.rope] = 30;
      g.sendVoyage(ostmark, {Resource.rope: 200});
      final v = g.voyages.first;
      expect(v.quotedCoin, g.quoteVoyage(ostmark, v.cargo),
          reason: 'never quote for cargo that was never loaded');
    });

    test('an empty hold is refused', () {
      final g = stocked();
      expect(g.sendVoyage(ostmark, {}), isFalse);
      expect(g.sendVoyage(ostmark, {Resource.rope: 0}), isFalse);
    });

    test('only so many hulls can be at sea', () {
      final g = stocked();
      for (var i = 0; i < Balance.maxVoyages; i++) {
        expect(g.sendVoyage(ostmark, {Resource.rope: 10}), isTrue);
      }
      expect(g.canSendVoyage, isFalse);
      expect(g.sendVoyage(ostmark, {Resource.rope: 10}), isFalse);
    });

    test('an escort costs powder and halves the risk', () {
      final g = stocked();
      expect(g.sendVoyage(ostmark, {Resource.rope: 10}, escorted: true), isFalse,
          reason: 'no powder, no escort');

      g.stock[Resource.powder] = 50;
      final before = g.stock[Resource.powder];
      expect(g.sendVoyage(ostmark, {Resource.rope: 10}, escorted: true), isTrue);
      expect(g.stock[Resource.powder],
          closeTo(before - Balance.escortPowderCost, 1e-6));
      expect(g.voyages.first.escorted, isTrue);
    });

    test('voyages round-trip through a save', () {
      final g = stocked();
      g.sendVoyage(ostmark, {Resource.rope: 100, Resource.tools: 20});
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);

      expect(restored.voyages, hasLength(1));
      final v = restored.voyages.first;
      expect(v.destinationId, 'ostmark');
      expect(v.returnTick, g.voyages.first.returnTick);
      expect(v.quotedCoin, g.voyages.first.quotedCoin);
      expect(v.cargo[Resource.rope], closeTo(100, 1e-6));
    });

    test('a save with no voyages block still loads', () {
      final g = stocked();
      final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
      json.remove('voyages');
      expect(GameState.fromJson(json).voyages, isEmpty);
    });
  });

  retinueTests();
  quartermasterTests();
  destinationIdentityTests();

  group('destinations', () {
    test('every destination is coherent', () {
      for (final d in kDestinations) {
        expect(d.days, greaterThan(0), reason: d.id);
        expect(d.charterPerUnit, greaterThan(0), reason: d.id);
        expect(d.risk, inInclusiveRange(0, 0.5), reason: d.id);
        expect(d.wants, isNotEmpty, reason: d.id);
      }
    });

    test('ids are unique', () {
      final ids = kDestinations.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('longer crossings pay better, or there would be no reason to sail',
        () {
      final sorted = [...kDestinations]..sort((a, b) => a.days.compareTo(b.days));
      final best =
          sorted.map((d) => d.wants.values.reduce((a, b) => a > b ? a : b));
      expect(best.first, lessThan(best.last));
    });
  });
}

// ---------------------------------------------------------------------------

void retinueTests() {
  group('the retinue', () {
    test('hiring costs coin and puts them on the books', () {
      final g = stocked();
      final first = retainerAt(RetinueTrack.captain, 1)!;
      final coinBefore = g.coin;

      expect(g.hire(first), isTrue);
      expect(g.coin, coinBefore - first.coinCost);
      expect(g.captainLevel, 1);
      expect(g.retinueWageBill, first.dailyWage);
    });

    test('you must hire in order', () {
      final g = stocked();
      g.coin = 100000;
      final third = retainerAt(RetinueTrack.captain, 3)!;
      expect(g.canHire(third), isFalse);
      expect(g.hire(third), isFalse);
      expect(g.captainLevel, 0);
    });

    test('an unaffordable hire changes nothing', () {
      final g = stocked();
      g.coin = 10;
      final first = retainerAt(RetinueTrack.merchant, 1)!;
      expect(g.hire(first), isFalse);
      expect(g.merchantLevel, 0);
    });

    test('the wage is drawn every day, which is what makes it a decision', () {
      final g = stocked();
      g.hire(retainerAt(RetinueTrack.captain, 1)!);
      final coinBefore = g.coin;
      final bill = g.dailyWageBill + g.retinueWageBill;

      for (var i = 0; i < Balance.ticksPerDay; i++) {
        g.step();
      }
      expect(g.coin, coinBefore - bill);
    });

    test('paying someone off stops the wage', () {
      final g = stocked();
      g.hire(retainerAt(RetinueTrack.merchant, 1)!);
      expect(g.retinueWageBill, greaterThan(0));
      g.dismiss(RetinueTrack.merchant);
      expect(g.merchantLevel, 0);
      expect(g.retinueWageBill, 0);
    });

    test('a merchant improves what the quay pays', () {
      final plain = stocked();
      final withMerchant = stocked();
      withMerchant.hire(retainerAt(RetinueTrack.merchant, 1)!);

      Ship gull() => Ship(
            name: 'Gull',
            departTick: 9999,
            offers: [
              Offer(resource: Resource.rope, quantity: 100, pricePerUnit: 12)
            ],
          );

      final a = gull();
      final b = gull();
      final plainEarned = plain.sell(a, a.offers.first, 100);
      final betterEarned = withMerchant.sell(b, b.offers.first, 100);
      expect(betterEarned, greaterThan(plainEarned));
    });

    test('a merchant improves what a voyage pays', () {
      final plain = stocked();
      final withMerchant = stocked();
      withMerchant.hire(retainerAt(RetinueTrack.merchant, 1)!);
      final dest = destinationById('ostmark');

      expect(withMerchant.quoteVoyage(dest, {Resource.rope: 100}),
          greaterThan(plain.quoteVoyage(dest, {Resource.rope: 100})));
    });

    test('a captain makes NEW crossings shorter', () {
      final plain = stocked();
      final withCaptain = stocked();
      withCaptain.hire(retainerAt(RetinueTrack.captain, 1)!);
      final dest = destinationById('the_reaches');

      plain.sendVoyage(dest, {Resource.rope: 50});
      withCaptain.sendVoyage(dest, {Resource.rope: 50});

      final plainDays = plain.voyages.first.returnTick - plain.tick;
      final fastDays = withCaptain.voyages.first.returnTick - withCaptain.tick;
      expect(fastDays, lessThan(plainDays));
    });

    test('a captain never reels in a hull already at sea', () {
      // The whole distinction: you can buy a better fleet, never buy back a
      // crossing you have already committed to.
      final g = stocked();
      g.coin = 100000;
      g.sendVoyage(destinationById('the_reaches'), {Resource.rope: 50});
      final due = g.voyages.first.returnTick;

      g.hire(retainerAt(RetinueTrack.captain, 1)!);
      g.hire(retainerAt(RetinueTrack.captain, 2)!);
      g.hire(retainerAt(RetinueTrack.captain, 3)!);

      expect(g.voyages.first.returnTick, due,
          reason: 'hiring cannot shorten a voyage already underway');
    });

    test('a captain lowers the risk of losing a hull', () {
      final g = stocked();
      expect(g.voyageRiskFactor, 1.0);
      g.hire(retainerAt(RetinueTrack.captain, 1)!);
      expect(g.voyageRiskFactor, lessThan(1.0));
    });

    test('a crossing never collapses below a day', () {
      final g = stocked();
      g.coin = 100000;
      g.hire(retainerAt(RetinueTrack.captain, 1)!);
      g.hire(retainerAt(RetinueTrack.captain, 2)!);
      g.hire(retainerAt(RetinueTrack.captain, 3)!);
      g.sendVoyage(destinationById('ostmark'), {Resource.rope: 20});
      expect(g.voyages.first.returnTick - g.tick,
          greaterThanOrEqualTo(Balance.ticksPerDay));
    });

    test('every tier is a real step up and costs more', () {
      for (final track in RetinueTrack.values) {
        if (track == RetinueTrack.quartermaster) continue; // its own test
        for (var lvl = 2; lvl <= 3; lvl++) {
          final lower = retainerAt(track, lvl - 1)!;
          final upper = retainerAt(track, lvl)!;
          expect(upper.coinCost, greaterThan(lower.coinCost));
          expect(upper.dailyWage, greaterThan(lower.dailyWage));
          if (track == RetinueTrack.captain) {
            expect(upper.voyageSpeed, lessThan(lower.voyageSpeed));
            expect(upper.voyageRisk, lessThan(lower.voyageRisk));
          } else {
            expect(upper.sellBonus, greaterThan(lower.sellBonus));
            expect(upper.voyagePay, greaterThan(lower.voyagePay));
          }
        }
      }
    });

    test('the roster round-trips through a save', () {
      final g = stocked();
      g.coin = 100000;
      g.hire(retainerAt(RetinueTrack.captain, 1)!);
      g.hire(retainerAt(RetinueTrack.merchant, 1)!);
      g.hire(retainerAt(RetinueTrack.merchant, 2)!);

      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(restored.captainLevel, 1);
      expect(restored.merchantLevel, 2);
      expect(restored.retinueWageBill, g.retinueWageBill);
    });

    test('a save with no roster loads with nobody hired', () {
      final g = stocked();
      final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
      json.remove('captainLevel');
      json.remove('merchantLevel');
      final restored = GameState.fromJson(json);
      expect(restored.captainLevel, 0);
      expect(restored.merchantLevel, 0);
      expect(restored.sellBonus, 1.0);
    });
  });
}

// ---------------------------------------------------------------------------

/// A port big enough that the quartermaster is on offer.
GameState bigPort() {
  final g = stocked();
  g.coin = 100000;
  for (final id in [
    'sawmill', 'flax_field', 'ropewalk', 'weaver', 'mine', 'smithy',
    'cooperage', 'farm', 'forest_camp', 'fishing_wharf', 'flax_field',
    'sawmill', 'forest_camp', 'farm', 'ropewalk', 'weaver',
  ]) {
    g.unlocked.add(id);
    for (final r in Resource.values) {
      g.stock[r] = 400;
    }
    g.build(defById(id));
  }
  // Room to cart into: without storage headroom a full yard cannot be
  // emptied by anyone, hired or not.
  g.unlocked.add('warehouse');
  for (var i = 0; i < 6; i++) {
    g.stock[Resource.planks] = 400;
    g.build(defById('warehouse'));
  }
  for (final r in Resource.values) {
    g.stock[r] = 0;
  }
  g.stock[Resource.fish] = 500;
  g.stock[Resource.grain] = 500;
  g.population = 80;
  for (var i = 0; i < g.buildings.length; i++) {
    g.setWorkers(i, g.buildings[i].def.maxWorkers);
  }
  return g;
}

void quartermasterTests() {
  group('the quartermaster', () {
    test('is not on offer to a small port', () {
      final g = stocked();
      g.coin = 100000;
      final first = retainerAt(RetinueTrack.quartermaster, 1)!;
      expect(g.producingSheds, lessThan(first.requiresBuildings));
      expect(g.canHire(first), isFalse,
          reason: 'collecting by hand is the point early on');
      expect(g.hire(first), isFalse);
    });

    test('becomes available once the carting is genuinely tedious', () {
      final g = bigPort();
      final first = retainerAt(RetinueTrack.quartermaster, 1)!;
      expect(g.producingSheds, greaterThanOrEqualTo(first.requiresBuildings));
      expect(g.canHire(first), isTrue);
      expect(g.hire(first), isTrue);
    });

    test('the first tier actually carts, rather than only catching stalls', () {
      // The complaint: "the quartermaster didn't auto collect unless the yards
      // were full, which rarely happened". A hire that almost never fires is
      // indistinguishable from one that does not work.
      final g = bigPort();
      g.hire(retainerAt(RetinueTrack.quartermaster, 1)!);

      // Four days is well short of a yard filling, so anything carted in here
      // is the clerk doing his rounds rather than a stall being cleared.
      for (var d = 0; d < 4; d++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          g.step();
        }
      }
      expect(g.buildings.every((b) => b.holdFullness < 0.9), isTrue,
          reason: 'nothing should be anywhere near full this early');
      expect(g.stock[Resource.timber], greaterThan(0),
          reason: 'the rounds should have put timber in the stores');
    });

    test('every tier still guarantees no shed stalls', () {
      for (var lvl = 1; lvl <= 3; lvl++) {
        final g = bigPort();
        for (var l = 1; l <= lvl; l++) {
          g.hire(retainerAt(RetinueTrack.quartermaster, l)!);
        }
        for (var i = 0; i < kHoldTicks.toInt() * 2; i++) {
          g.step();
        }
        for (final b in g.buildings) {
          expect(b.holdFullness, lessThan(0.999),
              reason: 'tier $lvl left ${b.defId} stalled');
        }
      }
    });

    test('a daily quartermaster carts the port in each evening', () {
      final g = bigPort();
      g.hire(retainerAt(RetinueTrack.quartermaster, 1)!);
      g.hire(retainerAt(RetinueTrack.quartermaster, 2)!);

      // Mid-day there is something waiting; after the day turns there is not.
      for (var i = 0; i < Balance.ticksPerDay ~/ 2; i++) {
        g.step();
      }
      expect(g.pendingCollection, greaterThan(0));

      for (var i = 0; i < Balance.ticksPerDay; i++) {
        g.step();
      }
      // The evening cart ran at the day boundary.
      expect(g.logEntries, isNotEmpty);
    });

    test('a harbour steward leaves nothing in a yard', () {
      final g = bigPort();
      for (var lvl = 1; lvl <= 3; lvl++) {
        g.hire(retainerAt(RetinueTrack.quartermaster, lvl)!);
      }
      for (var i = 0; i < 50; i++) {
        g.step();
      }
      expect(g.pendingCollection, closeTo(0, 1e-6));
      expect(g.hasAnythingToCollect, isFalse);
    });

    test('it carts while you are away, which is when stalls would happen', () {
      final g = bigPort();
      g.hire(retainerAt(RetinueTrack.quartermaster, 1)!);
      // Long enough that yards would fill twice over unattended, short enough
      // that the stores still have room to cart into — past that, storage is
      // the limiter and no quartermaster can help.
      g.catchUp(const Duration(minutes: 5), ticksPerSecond: 1.0);
      for (final b in g.buildings) {
        expect(b.holdFullness, lessThan(0.999), reason: b.defId);
      }
    });

    test('nothing is conjured — carting only moves what was made', () {
      final withClerk = bigPort();
      final without = bigPort();
      withClerk.hire(retainerAt(RetinueTrack.quartermaster, 3)!);
      // Level 3 needs the lower tiers; hire them properly.
      final fresh = bigPort();
      for (var lvl = 1; lvl <= 3; lvl++) {
        fresh.hire(retainerAt(RetinueTrack.quartermaster, lvl)!);
      }

      for (var i = 0; i < 40; i++) {
        fresh.step();
        without.step();
      }
      // Same production either way; the difference is only where it sits.
      final autoTotal =
          fresh.stock[Resource.timber] + fresh.pendingCollection;
      final handTotal =
          without.stock[Resource.timber] + without.pendingCollection;
      expect(autoTotal, lessThanOrEqualTo(handTotal + 1e-6));
    });

    test('it costs coin to sign and a wage every day', () {
      final g = bigPort();
      final r = retainerAt(RetinueTrack.quartermaster, 1)!;
      final before = g.coin;
      g.hire(r);
      expect(g.coin, before - r.coinCost);
      expect(g.retinueWageBill, r.dailyWage);
    });

    test('paying them off puts the carting back in your hands', () {
      final g = bigPort();
      g.hire(retainerAt(RetinueTrack.quartermaster, 1)!);
      expect(g.autoCollectMode, isNot(AutoCollect.none));
      g.dismiss(RetinueTrack.quartermaster);
      expect(g.autoCollectMode, AutoCollect.none);
      expect(g.quartermasterLevel, 0);
    });

    test('every tier costs more and does more', () {
      const order = [
        AutoCollect.everyOtherDay,
        AutoCollect.daily,
        AutoCollect.hourly,
      ];
      for (var lvl = 1; lvl <= 3; lvl++) {
        final r = retainerAt(RetinueTrack.quartermaster, lvl)!;
        expect(r.autoCollect, order[lvl - 1]);
        if (lvl > 1) {
          final lower = retainerAt(RetinueTrack.quartermaster, lvl - 1)!;
          expect(r.coinCost, greaterThan(lower.coinCost));
          expect(r.dailyWage, greaterThan(lower.dailyWage));
          expect(r.requiresBuildings, greaterThan(lower.requiresBuildings));
        }
      }
    });

    test('the roster round-trips through a save', () {
      final g = bigPort();
      g.hire(retainerAt(RetinueTrack.quartermaster, 1)!);
      g.hire(retainerAt(RetinueTrack.quartermaster, 2)!);

      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(restored.quartermasterLevel, 2);
      expect(restored.autoCollectMode, AutoCollect.daily);
    });

    test('a save with no quartermaster loads with nobody carting', () {
      final g = bigPort();
      final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
      json.remove('quartermasterLevel');
      expect(GameState.fromJson(json).autoCollectMode, AutoCollect.none);
    });
  });
}

// ---------------------------------------------------------------------------

void destinationIdentityTests() {
  group('destinations are actually different', () {
    /// Roughly when each cargo becomes available to a player.
    const stageOf = <Resource, String>{
      Resource.timber: 'early',
      Resource.grain: 'early',
      Resource.fish: 'early',
      Resource.flax: 'early',
      Resource.planks: 'early',
      Resource.ore: 'mid',
      Resource.rope: 'mid',
      Resource.barrels: 'mid',
      Resource.sailcloth: 'mid',
      Resource.tools: 'late',
      Resource.spirits: 'late',
      Resource.powder: 'late',
    };

    Destination bestFor(Resource r) => kDestinations
        .reduce((a, b) => a.dailyRateFor(r) >= b.dailyRateFor(r) ? a : b);

    test('no single port is the answer at any stage of the game', () {
      // The complaint: "everything sells best at Ostmark, which defeats the
      // purpose". The cause was differentiating ports on goods a player does
      // not own for the first hundred days. Every stage must offer a real
      // choice between at least two ports.
      for (final stage in {'early', 'mid', 'late'}) {
        final cargo = stageOf.entries
            .where((e) => e.value == stage)
            .map((e) => e.key);
        final ports = cargo.map((r) => bestFor(r).id).toSet();
        expect(ports.length, greaterThanOrEqualTo(2),
            reason: 'in the $stage game every cargo routes to '
                '${ports.join()} — there is no decision to make');
      }
    });

    test('every port is the best home for something', () {
      // The complaint that started this: "there is no reason to use the
      // others". Each destination must win outright for at least one cargo on
      // coin per day, which is the comparison that decides where a hull goes.
      final winners = <String, List<Resource>>{
        for (final d in kDestinations) d.id: [],
      };
      for (final r in Resource.values) {
        final best = kDestinations
            .reduce((a, b) => a.dailyRateFor(r) >= b.dailyRateFor(r) ? a : b);
        winners[best.id]!.add(r);
      }
      for (final d in kDestinations) {
        expect(winners[d.id], isNotEmpty,
            reason: '${d.name} is never the right answer for anything');
      }
    });

    test('the far port is not simply the near port with bigger numbers', () {
      final near = destinationById('ostmark');
      final far = destinationById('the_reaches');
      // Rope is Ostmark's trade; nine days away cannot beat three round trips.
      expect(near.dailyRateFor(Resource.rope),
          greaterThan(far.dailyRateFor(Resource.rope)));
      // Contraband is the Reaches' trade and nowhere else comes close.
      expect(far.dailyRateFor(Resource.spirits),
          greaterThan(near.dailyRateFor(Resource.spirits)));
    });

    test('carrying the wrong cargo is clearly wrong, not merely worse', () {
      final greyhaven = destinationById('greyhaven');
      // Timber to a garrison town should be plainly a bad idea.
      expect(greyhaven.payFor(Resource.timber), Destination.wrongCargoRate);
      expect(Destination.wrongCargoRate, lessThan(0.8),
          reason: 'at 0.9 every port felt interchangeable');
    });

    test('a longer haul is paid for in time, not just in risk', () {
      final sorted = [...kDestinations]..sort((a, b) => a.days.compareTo(b.days));
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i].risk, greaterThan(sorted[i - 1].risk));
        final bestNear = sorted[i - 1].wants.values.reduce((a, b) => a > b ? a : b);
        final bestFar = sorted[i].wants.values.reduce((a, b) => a > b ? a : b);
        expect(bestFar, greaterThan(bestNear));
      }
    });
  });
}
