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

void main() {
  group('no relief for sale', () {
    // THE RULE THIS WHOLE SYSTEM IS BUILT AGAINST. Pressure is the point; a
    // purchase that makes the pressure go away is the pattern. Notoriety set
    // the shape — no bribe, no passive decay, but a way down through play —
    // and happiness answers the same way.
    test('coin cannot buy a happier town', () {
      GameState run({required int coin}) {
        final g = GameState.newGame(seed: 4242);
        g.happiness = 0.2;
        g.coin = coin;
        play(g, 5);
        return g;
      }

      final poor = run(coin: 400);
      final rich = run(coin: 5000000);
      // A fortune pays wages, which is a legitimate way up — but only to the
      // same place the modest port reaches by also paying them.
      expect(rich.happiness, closeTo(poor.happiness, 0.02),
          reason: 'a fortune must not buy a mood a working port cannot earn');
    });

    test('it does not drift up on its own', () {
      // Nothing to wait out. A port doing badly stays badly-off until
      // something about how it is run changes.
      final g = GameState.newGame(seed: 7);
      g.happiness = 0.2;
      g.coin = 0; // wages unmet, so the target is genuinely low
      final before = g.happiness;
      play(g, 6);
      expect(g.happiness, lessThanOrEqualTo(before + 1e-9),
          reason: 'time alone must not fix a badly run port');
    });
  });

  group('what moves it', () {
    test('an unpaid crew is the sharpest way down', () {
      final g = GameState.newGame(seed: 3);
      g.coin = 0;
      final target = g.happinessTarget;
      expect(target, lessThan(Balance.happinessNeutral));
      expect(g.happinessReasons.first, contains('wages'));
    });

    test('feeding people well is what the herds buy', () {
      // Not calories — the meat only breaks even on those. Variety.
      final plain = GameState.newGame(seed: 11);
      final fed = GameState.newGame(seed: 11);
      fed.stock[Resource.meat] = 200;
      fed.stock[Resource.milk] = 200;
      play(plain, 3);
      play(fed, 3);

      expect(fed.mealQuality, greaterThan(0),
          reason: 'a port eating meat is eating something other than fish');
      expect(fed.happinessTarget, greaterThan(plain.happinessTarget));
    });

    test('a smuggler-ridden port is a worse place to live', () {
      final clean = GameState.newGame(seed: 5);
      final hot = GameState.newGame(seed: 5);
      hot.notoriety = 80;
      expect(hot.happinessTarget, lessThan(clean.happinessTarget));
    });

    test('a pet lifts it, and is the only unconditional good in one', () {
      final without = GameState.newGame(seed: 9);
      final with_ = GameState.newGame(seed: 9);
      with_.pet = PetKind.cat;
      expect(with_.happinessTarget,
          closeTo(without.happinessTarget + Balance.petHappiness, 1e-9));

      // A hungry animal is not cheering anybody up.
      with_.petFed = false;
      expect(with_.happinessTarget, closeTo(without.happinessTarget, 1e-9));
    });
  });

  group('teeth', () {
    test('an unhappy town stops growing, and says why', () {
      final g = GameState.newGame(seed: 13);
      g.happiness = 0.1;
      g.coin = 99999;
      g.stock[Resource.fish] = 500;
      final blocker = g.growthBlocker;
      expect(blocker, isNotNull);
      expect(blocker, contains('nobody new'),
          reason: 'growth stopping without an explanation is the fault this '
              'codebase keeps having to fix');
    });

    test('a miserable port loses people', () {
      final g = GameState.newGame(seed: 17);
      g.happiness = 0.0;
      g.coin = 0;
      g.stock[Resource.fish] = 500; // well fed, so this is misery not famine
      final before = g.population;
      play(g, 4);
      expect(g.population, lessThan(before));
    });

    test('there is a wide band between stalled and collapsing', () {
      // A port can sit unable to grow for a long time and still be pulled
      // round. Losing people is the floor, not the first consequence.
      expect(Balance.happinessExodusFloor,
          lessThan(Balance.happinessGrowthFloor - 0.1));
    });

    test('mood moves a day of work, but not by much', () {
      final g = GameState.newGame(seed: 19);
      g.happiness = 1.0;
      final best = g.happinessWorkFactor;
      g.happiness = 0.0;
      final worst = g.happinessWorkFactor;
      expect(best, greaterThan(worst));
      expect(best - worst, lessThan(0.25),
          reason: 'happiness is a pressure to read, not a second economy');
    });
  });

  test('it survives a save', () {
    final g = GameState.newGame(seed: 23);
    g.happiness = 0.37;
    final back = GameState.fromJson(
        jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
    expect(back.happiness, closeTo(0.37, 1e-3));
  });

  test('a save from before happiness existed starts level', () {
    final g = GameState.newGame(seed: 29);
    final j = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
    j.remove('happiness');
    expect(GameState.fromJson(j).happiness, Balance.happinessNeutral);
  });
}
