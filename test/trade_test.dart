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

/// Grow the port until it can keep [want] officers on the books.
///
/// A starting port supports one, which is the point of the cap — so any test
/// that retains two tracks has to build up to it first, exactly as a player
/// does. The sheds must be *staffed*: berths count hands at work, precisely so
/// that a row of empty huts cannot buy the cap out.
void openBerths(GameState g, int want) {
  var guard = 0;
  while (g.officerCapacity < want) {
    if (++guard > 60) {
      throw StateError('could not reach $want berths — is officerCapacity '
          'still keyed on something this loop can grow?');
    }
    g.buildings.add(Building(defId: 'fishing_wharf'));
    g.population += 1;
    g.placeAll();
    g.setWorkers(g.buildings.length - 1, 1);
  }
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

    test('you may ship the food out from under your own town', () {
      // DELIBERATE, and recorded here so it does not get "fixed" later. A
      // played run loaded a consignment on day 73, went from 9.6 days of food
      // to none overnight, and starved for five days losing five people. A
      // warning was built and then cut on the call that trading away your own
      // larder is the player's business: "if people trade too much that's on
      // them". Nothing guards it, and nothing should.
      final g = stocked();
      g.stock.add(Resource.fish, 200);
      expect(g.foodDays, greaterThan(4), reason: 'a fed town to start from');

      final larder = g.stock[Resource.fish];
      expect(g.sendVoyage(ostmark, {Resource.fish: larder}), isTrue,
          reason: 'the sim must not refuse a cargo that empties the stores');
      expect(g.foodDays, lessThan(4),
          reason: 'and the town is left genuinely short, with no rescue');
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
  autoCollectTests();
  privateerCaptainTests();
  destinationIdentityTests();
  retinuePricingTests();

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

    // Reported from play: "bought the first level of merchant at day 25 and it
    // is a no-brainer buy for every run". It was — a flat 5c/day wage against a
    // percentage of a cargo that grows all run is free money by construction.
    // These two tests pin the fixes so the shape cannot drift back.
    test('a small port has only one berth, so the first hire is a choice', () {
      final g = stocked();
      g.coin = 100000;
      expect(g.officerCapacity, 1,
          reason: 'a starting port supports one officer');

      expect(g.hire(retainerAt(RetinueTrack.merchant, 1)!), isTrue);
      expect(g.hasFreeOfficerBerth, isFalse);

      // A second *track* is refused while the one berth is taken.
      expect(g.canHire(retainerAt(RetinueTrack.captain, 1)!), isFalse);

      // Promoting the person you already keep is not a second officer.
      expect(g.canHire(retainerAt(RetinueTrack.merchant, 2)!), isTrue);

      // Paying them off frees the berth again.
      g.dismiss(RetinueTrack.merchant);
      expect(g.canHire(retainerAt(RetinueTrack.captain, 1)!), isTrue);
    });

    test('every captain saves real time on every lane', () {
      // Found by showing the number to the player: crossings were rounded to
      // whole days, so a first captain on the 3-day lane turned 2.55 into 3
      // and delivered nothing while still taking her commission — a trap on
      // the shortest, most-used route, bought by the first hire of the run.
      // Crossings are measured in hours now.
      final g = stocked();
      for (final dest in kDestinations) {
        g.captainLevel = 0;
        final bare = g.daysBreakdown(dest);
        expect(bare.days, dest.days.toDouble());

        for (final level in [1, 2, 3]) {
          g.captainLevel = level;
          final withCaptain = g.daysBreakdown(dest);
          expect(withCaptain.ticks, lessThan(bare.ticks),
              reason: 'captain L$level must actually shorten the '
                  '${dest.days}-day run to ${dest.name}, not round back to it');
        }
      }
      g.captainLevel = 0;
    });

    test('the panel quotes the crossing the hull actually sails', () {
      final g = stocked();
      g.coin = 100000;
      g.stock[Resource.planks] = 300;
      openBerths(g, 1);
      g.hire(retainerAt(RetinueTrack.captain, 1)!);

      final dest = kDestinations.first;
      final quoted = g.daysBreakdown(dest);
      final before = g.tick;
      expect(g.sendVoyage(dest, {Resource.planks: 40.0}), isTrue);

      expect(g.voyages.last.returnTick - before, quoted.ticks,
          reason: 'a panel that rounds differently from the hull quotes a '
              'crossing the ship does not sail');
    });

    test('a crossing sails under the terms it left on', () {
      // The captain's commission comes out of the quote at departure, so their
      // protection has to be fixed at departure too. Read live at settlement,
      // it could be bought for hulls already at sea by hiring while they were
      // out — the benefit without the cut.
      final g = stocked();
      g.coin = 100000;
      g.stock[Resource.planks] = 200;

      g.captainLevel = 0;
      expect(
          g.sendVoyage(kDestinations.first, {Resource.planks: 40.0}), isTrue);
      final sailed = g.voyages.last;
      expect(sailed.riskFactor, 1.0, reason: 'she left with nobody aboard');

      // Hiring now must not reach back and protect her.
      openBerths(g, 1);
      g.hire(retainerAt(RetinueTrack.captain, 1)!);
      expect(g.voyageRiskFactor, lessThan(1.0));
      expect(sailed.riskFactor, 1.0,
          reason: 'a hull already at sea keeps the terms she sailed under');

      // And the frozen factor survives a save.
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(restored.voyages.last.riskFactor, 1.0);
    });

    test('empty huts cannot buy a berth', () {
      // The cap keys off staffed sheds, not built ones. Counting built sheds
      // meant a player could throw up cheap huts nobody worked in and unlock
      // all three officers for a few hundred coin, which is exactly the pacing
      // gate the cap exists to be.
      final g = stocked();
      g.coin = 100000;
      for (var i = 0; i < 20; i++) {
        g.buildings.add(Building(defId: 'fishing_wharf'));
      }
      g.placeAll();

      final staffedBefore = g.staffedSheds;
      expect(g.producingSheds, greaterThanOrEqualTo(16),
          reason: 'enough BUILT sheds to have unlocked every berth');
      expect(g.staffedSheds, staffedBefore,
          reason: 'not one of the new huts has a hand in it');
      expect(g.officerCapacity, 1,
          reason: 'so a field of empty huts buys no berths at all');
    });

    test('a staffed import berth counts toward officers', () {
      // Reported from play: "import berth doesn't count towards officers". It
      // has no `outputs` map — it spends coin by the hour and lands raws
      // through a different path — so a test for outputs alone ignored a shed
      // with three hands posted to it. It produces by buying rather than by
      // making, which is still producing.
      final g = stocked();
      g.population = 60;
      final before = g.staffedSheds;
      final producingBefore = g.producingSheds;

      for (var i = 0; i < 4; i++) {
        g.buildings.add(Building(defId: 'import_berth'));
      }
      g.placeAll();
      for (var i = 0; i < g.buildings.length; i++) {
        if (g.buildings[i].def.imports) g.setWorkers(i, 3);
      }

      expect(g.staffedSheds, before + 4,
          reason: 'four worked import berths are four working sheds');

      // But an *unworked* one still counts for nothing, or the huts exploit
      // simply moves to a different building.
      final idle = GameState.newGame(seed: 3);
      final idleBefore = idle.staffedSheds;
      idle.buildings.add(Building(defId: 'import_berth'));
      idle.placeAll();
      expect(idle.staffedSheds, idleBefore,
          reason: 'an import berth with nobody in it is still an empty hut');

      // And it is still absent from the producing-shed count, deliberately:
      // imports land in the stores, so there is no yard to cart.
      expect(g.producingSheds, producingBefore,
          reason: 'an import berth has no yard, so it does not add to the '
              'count that drives automatic carting');
    });

    test('a save from before berths existed is brought within the cap', () {
      final g = stocked();
      g.coin = 100000;
      openBerths(g, 3);
      g.buildings.add(Building(defId: 'privateer_berth'));
      g.placeAll();
      g.hire(retainerAt(RetinueTrack.captain, 1)!);
      g.hire(retainerAt(RetinueTrack.merchant, 1)!);
      g.hire(retainerAt(RetinueTrack.privateer, 1)!);
      expect(g.officersRetained, 3);

      // The port shrinks below what three officers need — or the save predates
      // the cap entirely, which is the same shape of problem.
      for (final b in g.buildings) {
        b.workers = 0;
      }

      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);

      expect(restored.officersRetained,
          lessThanOrEqualTo(restored.officerCapacity),
          reason: 'loading must not leave a roster exempt from the cap that '
              'every later run has to live with');
    });

    test('commission scales with the cargo, so no hire is ever free money', () {
      final g = stocked();
      final small = {Resource.planks: 60.0, Resource.rope: 40.0};
      final large = {Resource.planks: 600.0, Resource.rope: 400.0};
      final dest = kDestinations.first;

      g.merchantLevel = 0;
      final smallPlain = g.quoteVoyage(dest, small);
      final largePlain = g.quoteVoyage(dest, large);
      g.merchantLevel = 1;
      final smallHired = g.quoteVoyage(dest, small);
      final largeHired = g.quoteVoyage(dest, large);

      // Worth having...
      expect(smallHired, greaterThan(smallPlain));

      // ...but the gain stays a roughly constant *share* of the cargo rather
      // than widening against a fixed wage. Under the old flat wage this ratio
      // grew without limit, which is what made the hire a formality.
      final smallShare = (smallHired - smallPlain) / smallPlain;
      final largeShare = (largeHired - largePlain) / largePlain;
      expect((largeShare - smallShare).abs(), lessThan(0.02),
          reason: 'the merchant takes a cut, so their edge does not run away '
              'with the size of the consignment');
    });

    test('a captain trades coin for speed rather than adding both', () {
      final g = stocked();
      final dest = kDestinations.first;
      final cargo = {Resource.planks: 60.0, Resource.rope: 40.0};

      g.captainLevel = 0;
      final plain = g.quoteVoyage(dest, cargo);
      g.captainLevel = 1;
      final hired = g.quoteVoyage(dest, cargo);

      // The captain sells speed and safety, and takes a share of the venture
      // for it. A crossing under a retained captain pays *less*, not more —
      // the gain has to come from sailing more of them.
      expect(hired, lessThan(plain));
      expect(g.voyageSpeedFactor, lessThan(1.0));
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
        for (var lvl = 2; lvl <= 3; lvl++) {
          final lower = retainerAt(track, lvl - 1)!;
          final upper = retainerAt(track, lvl)!;
          expect(upper.coinCost, greaterThan(lower.coinCost));
          expect(upper.dailyWage, greaterThan(lower.dailyWage));
          if (track == RetinueTrack.captain) {
            expect(upper.voyageSpeed, lessThan(lower.voyageSpeed));
            expect(upper.voyageRisk, lessThan(lower.voyageRisk));
          } else if (track == RetinueTrack.privateer) {
            expect(upper.prizeBonus, greaterThan(lower.prizeBonus));
            expect(upper.bootyBonus, greaterThan(lower.bootyBonus));
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
      openBerths(g, 2); // two tracks at once needs a port big enough for them
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

/// A port large enough to cart itself, and to seat three officers.
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

void autoCollectTests() {
  group('automatic carting', () {
    // Carting used to be a paid officer, the quartermaster. A player was right
    // that convenience should not compete for coin or a berth against the
    // captain and merchant, so it is no longer hired — it escalates on its own
    // as the port grows, at the quartermaster's old building gates.
    test('the tier follows the port size, at the old gates', () {
      expect(autoCollectFor(4), AutoCollect.none);
      expect(autoCollectFor(5), AutoCollect.everyOtherDay);
      expect(autoCollectFor(9), AutoCollect.daily);
      expect(autoCollectFor(13), AutoCollect.hourly);
    });

    test('a small port carts nothing — collecting by hand is the point', () {
      final g = stocked();
      expect(g.producingSheds, lessThan(5));
      expect(g.autoCollectMode, AutoCollect.none);
    });

    test('a large port carts on its own, with nobody hired', () {
      final g = bigPort();
      expect(g.producingSheds, greaterThanOrEqualTo(13));
      expect(g.autoCollectMode, AutoCollect.hourly);
      expect(g.officersRetained, 0, reason: 'carting is no longer an officer');
    });

    test('the rounds actually cart, not only catch stalls', () {
      // The old complaint: carting that only fired when a yard was already
      // full "rarely happened". Four days is well short of a yard filling.
      final g = bigPort();
      for (var d = 0; d < 4; d++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          g.step();
        }
      }
      expect(g.buildings.every((b) => b.holdFullness < 0.9), isTrue,
          reason: 'nothing should be near full this early');
      expect(g.stock[Resource.timber], greaterThan(0),
          reason: 'the rounds should have put timber in the stores');
    });

    test('an hourly port leaves nothing in a yard', () {
      final g = bigPort();
      for (var i = 0; i < 50; i++) {
        g.step();
      }
      expect(g.pendingCollection, closeTo(0, 1e-6));
      expect(g.hasAnythingToCollect, isFalse);
    });

    test('no shed stalls, even unattended', () {
      final g = bigPort();
      // Long enough that yards would fill unattended, short enough that the
      // stores still have room to cart into.
      g.catchUp(const Duration(minutes: 5), ticksPerSecond: 1.0);
      for (final b in g.buildings) {
        expect(b.holdFullness, lessThan(0.999), reason: b.defId);
      }
    });

    test('nothing is conjured — carting only moves what was made', () {
      final auto = bigPort();
      // A hand-collected port of the same size: same production, the surplus
      // just sits in the yards instead of the stores.
      final byHand = bigPort();
      for (var i = 0; i < 40; i++) {
        auto.step();
        byHand.step();
      }
      final autoTotal = auto.stock[Resource.timber] + auto.pendingCollection;
      final handTotal = byHand.stock[Resource.timber] + byHand.pendingCollection;
      expect(autoTotal, lessThanOrEqualTo(handTotal + 1e-6));
    });

    test('carting is free — it adds nothing to the wage bill', () {
      final g = bigPort();
      expect(g.autoCollectMode, AutoCollect.hourly);
      expect(g.retinueWageBill, 0,
          reason: 'the port carts itself; no wage is owed for it');
    });

    test('a reloaded port still carts by its size', () {
      final g = bigPort();
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(restored.autoCollectMode, AutoCollect.hourly);
    });

    test('a save that still holds a quartermasterLevel loses only the wage', () {
      // Old saves carried a hired quartermaster. Loading one must not crash,
      // and carting simply becomes automatic — the freed berth is a quiet buff.
      final g = bigPort();
      final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
      json['quartermasterLevel'] = 2;
      final restored = GameState.fromJson(json);
      expect(restored.officersRetained, 0);
      expect(restored.autoCollectMode, AutoCollect.hourly);
    });
  });
}

/// A port carrying a privateer berth, so the pirate captain is on offer.
GameState darkPort() {
  final g = bigPort();
  g.buildings.add(Building(defId: 'privateer_berth'));
  g.placeAll();
  g.setWorkers(g.buildings.length - 1, 4);
  g.coin = 100000;
  return g;
}

void privateerCaptainTests() {
  group('the privateer captain', () {
    test('is not offered to a port with no privateer berth', () {
      final g = bigPort();
      g.coin = 100000;
      final first = retainerAt(RetinueTrack.privateer, 1)!;
      expect(first.requiresBuilding, 'privateer_berth');
      expect(g.canHire(first), isFalse,
          reason: 'an honest port has no use for a pirate captain');
    });

    test('is offered once a privateer berth stands', () {
      final g = darkPort();
      openBerths(g, 3);
      final first = retainerAt(RetinueTrack.privateer, 1)!;
      expect(g.canHire(first), isTrue);
      expect(g.hire(first), isTrue);
      expect(g.privateerLevel, 1);
    });

    test('lifts the odds at the rail', () {
      final base = darkPort();
      final withCap = darkPort();
      openBerths(withCap, 3);
      withCap.hire(retainerAt(RetinueTrack.privateer, 1)!);

      final ship = Ship(name: 'Prize', departTick: 99999, offers: const [],
          foreign: true, prizeTons: 60);
      expect(withCap.prizeSuccessChance(ship),
          greaterThan(base.prizeSuccessChance(ship)));
    });

    test('lands a fuller hold', () {
      // Measured, not asserted from the constant: a fully captained boarding
      // lands meaningfully more spice than an uncaptained one. Storage
      // headroom matters — the first attempt at this measured nothing because
      // spice capped at the store limit and hid the difference entirely.
      double spiceFromOnePrize(int level) {
        final g = GameState.newGame(seed: 424242);
        g.population = 60;
        g.coin = 200000;
        g.buildings.add(Building(defId: 'privateer_berth'));
        for (var i = 0; i < 10; i++) {
          g.buildings.add(Building(defId: 'warehouse')); // headroom
        }
        g.placeAll();
        g.setWorkers(g.buildings.length - 11, 4);
        g.privateerLevel = level;
        for (var i = 0; i < 50; i++) {
          final before = g.stock[Resource.spice];
          final ship = Ship(
              name: 'Prize',
              departTick: g.tick + 50,
              offers: const [],
              foreign: true,
              prizeTons: 70);
          g.market.ships.add(ship);
          g.stock[Resource.powder] = 100;
          if (g.takePrize(ship)) return g.stock[Resource.spice] - before;
          g.market.ships.remove(ship);
        }
        return 0;
      }

      final plain = spiceFromOnePrize(0);
      final captained = spiceFromOnePrize(3);
      expect(plain, greaterThan(0), reason: 'the control boarding must land');
      expect(captained, greaterThan(plain * 1.4),
          reason: 'a pirate captain must visibly fill the hold');
    });

    test('every tier lifts both odds and booty', () {
      for (var lvl = 2; lvl <= 3; lvl++) {
        final lower = retainerAt(RetinueTrack.privateer, lvl - 1)!;
        final upper = retainerAt(RetinueTrack.privateer, lvl)!;
        expect(upper.prizeBonus, greaterThan(lower.prizeBonus));
        expect(upper.bootyBonus, greaterThan(lower.bootyBonus));
        expect(upper.coinCost, greaterThan(lower.coinCost));
      }
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

// ---------------------------------------------------------------------------

void retinuePricingTests() {
  group('retinue pricing', () {
    test('the first rung of every track is an early-game decision', () {
      // Reported as "level 1 is a little high — by the time you get to them
      // it's already mid-late game". An upgrade you cannot afford until the
      // run is decided shapes nothing.
      for (final track in RetinueTrack.values) {
        final first = retainerAt(track, 1)!;
        expect(first.coinCost, lessThan(Balance.lighthouseCoin / 12),
            reason: '${first.name} at ${first.coinCost}c is too dear to be a '
                'decision you build a run around');
      }
    });

    test('a first hire is reachable not long after the port finds its feet',
        () {
      // Play an honest early game: work the sheds, cart them in, sell to
      // whoever calls. The first rung should be affordable well before the
      // lighthouse is in sight.
      final g = GameState.newGame(seed: 31415);
      var affordableOn = -1;
      final cheapest = RetinueTrack.values
          .map((t) => retainerAt(t, 1)!.coinCost)
          .reduce((a, b) => a < b ? a : b);

      for (var day = 1; day <= 60 && affordableOn < 0; day++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          g.step();
          g.collectAll();
          for (final ship in List.of(g.market.ships)) {
            for (final o in ship.offers.where((o) => !o.isFilled)) {
              if (o.resource.isFood) continue; // the town has to eat
              final spare = g.stock[o.resource] - 20;
              if (spare >= 1) g.sell(ship, o, spare);
            }
          }
        }
        if (g.coin >= cheapest) affordableOn = day;
      }

      expect(affordableOn, greaterThan(0),
          reason: 'no first hire was affordable in sixty days');
      expect(affordableOn, lessThan(40),
          reason: 'the first hire landed on day $affordableOn — too late to '
              'shape how the run is played');
    });

    test('each rung costs meaningfully more than the one below', () {
      for (final track in RetinueTrack.values) {
        for (var lvl = 2; lvl <= 3; lvl++) {
          final lower = retainerAt(track, lvl - 1)!;
          final upper = retainerAt(track, lvl)!;
          expect(upper.coinCost, greaterThan(lower.coinCost * 2),
              reason: '${upper.name} is barely dearer than ${lower.name}');
        }
      }
    });

  });
  _rankingTests();
}

void _rankingTests() {
  group('a port that pays more per unit can still be the worse voyage', () {
    // The exact confusion a player reported: "greyhaven pays better for tools
    // than the reaches yet the price on the reaches is higher". Both were
    // true. The hull, not the price, is what is scarce.
    test('tools: The Reaches pays far more per unit and still loses per day',
        () {
      final grey = kDestinations.firstWhere((d) => d.id == 'greyhaven');
      final reaches = kDestinations.firstWhere((d) => d.id == 'the_reaches');

      expect(reaches.payFor(Resource.tools),
          greaterThan(grey.payFor(Resource.tools)),
          reason: 'the headline multiplier is higher at The Reaches');
      expect(grey.dailyRateFor(Resource.tools),
          greaterThan(reaches.dailyRateFor(Resource.tools)),
          reason: 'and Greyhaven still wins on the rate that decides');
    });

    // Guards the fix rather than the balance: if ranking is ever "simplified"
    // to compare payFor, the two numbers on screen start contradicting each
    // other again and the game reads as broken.
    test('the daily rate accounts for the crossing and the freight', () {
      for (final d in kDestinations) {
        for (final r in Resource.values) {
          if (d.payFor(r) <= 1.0) continue;
          final gross = r.basePrice * d.payFor(r);
          expect(d.dailyRateFor(r), lessThan(gross),
              reason: '${d.name}/${r.label}: a daily rate that is not below '
                  'the gross per unit has stopped dividing by the crossing');
          expect(d.dailyRateFor(r),
              closeTo((gross - d.charterPerUnit) / d.days, 0.001));
        }
      }
    });
  });
}
