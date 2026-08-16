import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/sim/charters.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/profile.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:ports_ahoy/sim/trade.dart';

void main() {
  endOfRunTests();
  group('the risk budget', () {
    test('a run of pure advantages is arithmetically impossible', () {
      // The rule the whole system rests on: you can only make something
      // easier by first making something else harder.
      final everyAdvantage =
          CharterSet(kCharters.where((c) => !c.isHardship).toList());
      expect(everyAdvantage.isLegal, isFalse);

      // And the base budget is small enough that it buys very little.
      final cheapest = kCharters
          .where((c) => !c.isHardship)
          .map((c) => -c.weight)
          .reduce((a, b) => a < b ? a : b);
      expect(kBaseBudget, lessThan(cheapest * 3));
    });

    test('a hardship pays for an advantage of equal weight', () {
      final s = CharterSet([
        charterById('hard_weather')!, // +2
        charterById('rich_contracts')!, // -2
        charterById('deep_cellars')!, // -1, from the base budget
      ]);
      expect(s.budgetEarned, 2);
      expect(s.budgetSpent, 3);
      expect(s.isLegal, isTrue);
      expect(s.budgetLeft, 1);
    });

    test('overspending is refused', () {
      final s = CharterSet([
        charterById('rich_contracts')!, // -2
        charterById('fair_winds')!, // -2
        charterById('deep_cellars')!, // -1
      ]);
      expect(s.budgetSpent, 5);
      expect(s.isLegal, isFalse);
    });

    test('difficulty counts hardship only', () {
      final s = CharterSet([
        charterById('hard_weather')!, // +2
        charterById('poor_soil')!, // +1
        charterById('rich_contracts')!, // -2
      ]);
      expect(s.difficulty, 3, reason: 'advantages must not reduce difficulty');
    });

    test('every charter is coherent', () {
      final ids = <String>{};
      for (final c in kCharters) {
        expect(ids.add(c.id), isTrue, reason: 'duplicate ${c.id}');
        expect(c.weight, isNot(0), reason: '${c.id} costs and gives nothing');
        expect(c.name, isNotEmpty);
        expect(c.blurb, isNotEmpty);
      }
      expect(kCharters.where((c) => c.isHardship).length,
          greaterThanOrEqualTo(4));
      expect(kCharters.where((c) => !c.isHardship).length,
          greaterThanOrEqualTo(4));
    });
  });

  group('charters change the run', () {
    test('a full purse starts you richer', () {
      final plain = GameState.newGame();
      final rich = GameState.newGame(
          charters: CharterSet([charterById('a_full_purse')!]));
      expect(rich.coin, greaterThan(plain.coin));
    });

    test('willing hands start you with more people', () {
      final plain = GameState.newGame();
      final crewed = GameState.newGame(
          charters: CharterSet([charterById('willing_hands')!]));
      expect(crewed.population, plain.population + 3);
    });

    test('cramped stores really do hold less', () {
      final plain = GameState.newGame();
      final cramped = GameState.newGame(
          charters: CharterSet([charterById('cramped_stores')!]));
      expect(cramped.storageCapacity, lessThan(plain.storageCapacity));
    });

    test('poor soil slows every shed', () {
      final plain = GameState.newGame();
      final poor =
          GameState.newGame(charters: CharterSet([charterById('poor_soil')!]));
      for (var i = 0; i < 30; i++) {
        plain.step();
        poor.step();
      }
      plain.collectAll();
      poor.collectAll();
      expect(poor.stock[Resource.timber],
          lessThan(plain.stock[Resource.timber]));
    });

    test('a hungry town eats through its stores faster', () {
      final plain = GameState.newGame();
      final hungry = GameState.newGame(
          charters: CharterSet([charterById('hungry_town')!]));
      for (var d = 0; d < 3; d++) {
        for (var t = 0; t < Balance.ticksPerDay; t++) {
          plain.step();
          hungry.step();
        }
      }
      expect(hungry.foodDays, lessThan(plain.foodDays));
    });

    test('a grander light costs more of everything', () {
      final plain = GameState.newGame();
      final grand = GameState.newGame(
          charters: CharterSet([charterById('a_grander_light')!]));
      expect(grand.lighthouseCoinCost, greaterThan(plain.lighthouseCoinCost));
      expect(grand.lighthouseGoodsCost[Resource.planks],
          greaterThan(plain.lighthouseGoodsCost[Resource.planks]!));
    });

    test('rich contracts pay more for the same cargo', () {
      final plain = GameState.newGame();
      final rich = GameState.newGame(
          charters: CharterSet([charterById('rich_contracts')!]));
      final ostmark = destinationById('ostmark');
      expect(rich.quoteVoyage(ostmark, {Resource.rope: 100}),
          greaterThan(plain.quoteVoyage(ostmark, {Resource.rope: 100})));
    });

    test('thin purses pay less for the same cargo', () {
      final plain = GameState.newGame();
      final thin = GameState.newGame(
          charters: CharterSet([charterById('thin_purses')!]));
      final ostmark = destinationById('ostmark');
      expect(thin.quoteVoyage(ostmark, {Resource.rope: 100}),
          lessThan(plain.quoteVoyage(ostmark, {Resource.rope: 100})));
    });

    test('hard weather brings the storms round more often', () {
      expect(charterById('hard_weather')!.hazardGap, lessThan(1.0));
      expect(charterById('settled_coast')!.hazardGap, greaterThan(1.0));
    });

    test('the charters a run began under survive a save', () {
      final g = GameState.newGame(
          charters: CharterSet(
              [charterById('hard_weather')!, charterById('rich_contracts')!]));
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(restored.charters.ids.toSet(), g.charters.ids.toSet());
      expect(restored.charters.difficulty, g.charters.difficulty);
    });
  });

  group('the profile', () {
    test('it survives a run ending', () {
      final p = Profile(owned: {'hard_weather'}, active: {'hard_weather'});
      p.runs.add(const RunRecord(
          days: 120, difficulty: 2, population: 30, charterIds: []));
      final back = Profile.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(back.owned, p.owned);
      expect(back.active, p.active);
      expect(back.runs, hasLength(1));
      expect(back.runs.first.days, 120);
    });

    test('records are kept per difficulty', () {
      final p = Profile();
      p.runs.addAll(const [
        RunRecord(days: 120, difficulty: 0, population: 30, charterIds: []),
        RunRecord(days: 150, difficulty: 4, population: 30, charterIds: []),
        RunRecord(days: 140, difficulty: 4, population: 30, charterIds: []),
      ]);
      expect(p.bestByDifficulty[0]!.days, 120);
      expect(p.bestByDifficulty[4]!.days, 140,
          reason: 'a hard run should not compete with an easy one');
    });

    test('an offer never repeats what you already hold', () {
      final p = Profile(owned: kCharters.take(kCharters.length - 2).map((c) => c.id).toSet());
      final offer = p.offer(99);
      expect(offer.length, lessThanOrEqualTo(2));
      for (final id in offer) {
        expect(p.owned.contains(id), isFalse);
      }
    });

    test('an offer cannot be rerolled by restarting', () {
      final p = Profile();
      expect(p.offer(1234), p.offer(1234));
    });

    test('an illegal selection is trimmed rather than left broken', () {
      final p = Profile(
        owned: {'rich_contracts', 'fair_winds', 'deep_cellars'},
        active: {'rich_contracts', 'fair_winds', 'deep_cellars'},
      );
      p.reconcile();
      expect(p.activeSet.isLegal, isTrue);
      expect(p.active.length, lessThan(3));
    });

    test('activating a charter you do not own is impossible', () {
      final p = Profile(owned: {'poor_soil'}, active: {'poor_soil', 'fair_winds'});
      p.reconcile();
      expect(p.active, {'poor_soil'});
    });
  });
}

// ---------------------------------------------------------------------------

void endOfRunTests() {
  group('finishing a run', () {
    test('the light is no longer a dead end', () {
      // The gap this whole system exists to close: winning used to fire a
      // dialog and hand back a port with nothing left to do.
      final p = Profile();
      expect(p.wins, 0);
      expect(p.hasChoicePending, isFalse);

      p.runs.add(const RunRecord(
          days: 132, difficulty: 0, population: 41, charterIds: []));
      p.pendingChoice = p.offer(4242);

      expect(p.hasChoicePending, isTrue);
      expect(p.pendingChoice, hasLength(3),
          reason: 'a choice, not a handout');
    });

    test('a chosen charter is kept for good', () {
      final p = Profile();
      p.pendingChoice = p.offer(7);
      final picked = p.pendingChoice.first;
      p.owned.add(picked);
      p.pendingChoice = const [];

      final back = Profile.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(back.owned, contains(picked));
      expect(back.hasChoicePending, isFalse);
    });

    test('a new run under charters starts differently', () {
      final plain = GameState.newGame();
      final hard = GameState.newGame(
        charters: CharterSet([
          charterById('hard_weather')!,
          charterById('a_full_purse')!,
          charterById('willing_hands')!,
        ]),
      );
      expect(hard.coin, greaterThan(plain.coin));
      expect(hard.population, greaterThan(plain.population));
      expect(hard.charters.difficulty, 2);
      expect(hard.charters.isLegal, isTrue);
    });

    test('the collection grows but the budget does not', () {
      // Power creep is the failure mode of every unlock ladder that only adds.
      // Owning everything must not make a run any easier than owning two.
      final few = Profile(owned: {'rich_contracts', 'hard_weather'});
      final all = Profile(owned: kCharters.map((c) => c.id).toSet());
      for (final p in [few, all]) {
        p.active.addAll(p.owned);
        p.reconcile();
      }
      expect(few.activeSet.isLegal, isTrue);
      expect(all.activeSet.isLegal, isTrue);
      expect(all.activeSet.budgetSpent,
          lessThanOrEqualTo(all.activeSet.budgetEarned + kBaseBudget));
    });
  });
}
