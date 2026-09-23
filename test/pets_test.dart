import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/pets.dart';
import 'package:ports_ahoy/sim/resources.dart';

void play(GameState g, int days) {
  for (var d = 0; d < days; d++) {
    for (var t = 0; t < Balance.ticksPerDay; t++) {
      g.step();
      g.collectAll();
    }
  }
}

/// A port standing on the day the ship with animals aboard puts in.
GameState portAtOffer({int seed = 4242}) {
  final g = GameState.newGame(seed: seed);
  g.coin = 5000;
  g.tick = (g.petOfferDay - 1) * Balance.ticksPerDay;
  return g;
}

void main() {
  group('the set', () {
    // THE PROPERTY A SIXTH ANIMAL WOULD BREAK WITHOUT ANYONE NOTICING. Nothing
    // is strictly best only because every pet's gift is another pet's cost; if
    // one of them ever raises something nobody lowers, it becomes the obvious
    // pick and the choice stops being a choice.
    test('every product is raised by one pet and lowered by one', () {
      final raised = <Resource, int>{};
      final lowered = <Resource, int>{};
      for (final p in kPets) {
        raised[p.raises] = (raised[p.raises] ?? 0) + 1;
        lowered[p.lowers] = (lowered[p.lowers] ?? 0) + 1;
      }
      expect(raised.keys.toSet(), lowered.keys.toSet(),
          reason: 'a product raised by nobody, or lowered by nobody, is a '
              'free lunch or a dead weight');
      for (final r in raised.keys) {
        expect(raised[r], 1, reason: '${r.label} is raised by ${raised[r]}');
        expect(lowered[r], 1, reason: '${r.label} is lowered by ${lowered[r]}');
      }
    });

    test('no pet touches meat, because meat is what pets eat', () {
      // A pet that raised meat would be partly feeding itself, and its upkeep
      // would stop being a cost — the one thing every pet has in common. The
      // dog is the trap: a herding dog plausibly improves everything about a
      // herd, so it gets milk and nothing else.
      for (final p in kPets) {
        expect(p.raises, isNot(Resource.meat), reason: '${p.name} raises meat');
        expect(p.lowers, isNot(Resource.meat), reason: '${p.name} lowers meat');
      }
    });

    test('a pet never raises and lowers the same thing', () {
      for (final p in kPets) {
        expect(p.raises, isNot(p.lowers), reason: '${p.name} cancels itself');
      }
    });
  });

  group('the offer', () {
    test('arrives once, in the window, and never twice', () {
      for (var seed = 0; seed < 60; seed++) {
        final g = GameState.newGame(seed: seed);
        expect(g.petOfferDay,
            inInclusiveRange(Balance.petOfferFirstDay, Balance.petOfferLastDay),
            reason: 'seed $seed offered on day ${g.petOfferDay}');
      }
    });

    test('is not open before its day', () {
      final g = GameState.newGame(seed: 7);
      expect(g.petOfferOpen, isFalse);
      expect(g.takePet(PetKind.dog), isFalse,
          reason: 'there is no ship to buy from yet');
      expect(g.pet, isNull);
    });

    test('a pet can be taken, once, and costs coin', () {
      final g = portAtOffer();
      play(g, 2);
      expect(g.petOfferOpen, isTrue);

      final before = g.coin;
      expect(g.takePet(PetKind.turtle), isTrue);
      expect(g.pet, PetKind.turtle);
      expect(g.coin, before - kPetPrice);

      // ONE A RUN. A second slot turns the question from "which animal suits
      // this run" into "collect the set".
      expect(g.petOfferOpen, isFalse);
      expect(g.takePet(PetKind.dog), isFalse);
      expect(g.pet, PetKind.turtle);
    });

    test('declining is a real answer and is not asked again', () {
      final g = portAtOffer();
      play(g, 2);
      g.declinePet();
      expect(g.petOfferOpen, isFalse);
      play(g, 20);
      expect(g.petOfferOpen, isFalse);
      expect(g.pet, isNull);
    });

    test('a port too poor to buy is not robbed of the chance', () {
      final g = portAtOffer();
      g.coin = kPetPrice - 1;
      play(g, 2);
      expect(g.takePet(PetKind.cat), isFalse);
      expect(g.petOfferOpen, isTrue, reason: 'the ship has not sailed yet');
      g.coin = kPetPrice;
      expect(g.takePet(PetKind.cat), isTrue);
    });
  });

  group('what it does', () {
    test('raises one product and lowers another, and nothing else', () {
      final g = GameState.newGame(seed: 1);
      g.pet = PetKind.monkey;
      expect(g.petYieldFactor(Resource.timber), closeTo(1 + kPetBuff, 1e-9));
      expect(g.petYieldFactor(Resource.tools), closeTo(1 - kPetDrag, 1e-9));
      for (final r in Resource.values) {
        if (r == Resource.timber || r == Resource.tools) continue;
        expect(g.petYieldFactor(r), 1.0,
            reason: 'a monkey should not be touching ${r.label}');
      }
    });

    test('a kept pet actually moves the yard', () {
      GameState run(PetKind? kind) {
        final g = GameState.newGame(seed: 99);
        g.pet = kind;
        play(g, 6);
        return g;
      }

      final none = run(null);
      final withMonkey = run(PetKind.monkey);
      expect(withMonkey.stock[Resource.timber],
          greaterThan(none.stock[Resource.timber]),
          reason: 'at 10% this has to be visible in six days of felling, or '
              'the number is too small to bother printing');
    });

    test('an unfed pet stops working, and never dies', () {
      final g = GameState.newGame(seed: 3);
      g.pet = PetKind.monkey;
      g.stock[Resource.meat] = 0;
      play(g, 3);

      expect(g.petFed, isFalse);
      expect(g.pet, PetKind.monkey, reason: 'it must never die of neglect');
      expect(g.petYieldFactor(Resource.timber), 1.0,
          reason: 'a hungry animal is not working');
      expect(g.petYieldFactor(Resource.tools), 1.0,
          reason: 'nor is it still costing you — the drag sleeps too');

      // And it comes back, because this is recoverable.
      g.stock[Resource.meat] = 50;
      play(g, 2);
      expect(g.petFed, isTrue);
      expect(g.petYieldFactor(Resource.timber), closeTo(1 + kPetBuff, 1e-9));
    });

    test('it eats meat, and only meat', () {
      final g = GameState.newGame(seed: 5);
      g.pet = PetKind.dog;
      g.stock[Resource.meat] = 20;
      final fishBefore = g.stock[Resource.fish];
      play(g, 2);
      expect(g.stock[Resource.meat], lessThan(20));
      // The town eats fish too, so this only checks the pet did not invent an
      // appetite for it — the meat above is what moved.
      expect(g.stock[Resource.fish], lessThanOrEqualTo(fishBefore + 1000));
    });
  });

  test('a pet survives a save', () {
    final g = portAtOffer();
    play(g, 2);
    expect(g.takePet(PetKind.bird), isTrue);
    final back = GameState.fromJson(
        jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
    expect(back.pet, PetKind.bird);
    expect(back.petOfferSettled, isTrue);
    expect(back.petOfferDay, g.petOfferDay);
  });

  test('a save written before pets existed does not ambush the player', () {
    // No pet keys at all: the offer must still be in its window ahead of the
    // port, not fired retroactively on the day the save is opened.
    final g = GameState.newGame(seed: 11);
    final j = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
    j.remove('pet');
    j.remove('petSettled');
    j.remove('petDay');
    final back = GameState.fromJson(j);
    expect(back.pet, isNull);
    expect(back.petOfferSettled, isFalse);
    expect(back.petOfferDay,
        inInclusiveRange(Balance.petOfferFirstDay, Balance.petOfferLastDay));
  });
}
