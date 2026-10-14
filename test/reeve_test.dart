// The reeve, after he took over the grange's job.
//
// Two reports led here. "The reeve does feel skippable" — his only effect was
// ripening speed, and nothing on screen showed it. Then: "why would you not
// hire to get farms online then fire for another captain?" — a shed's growth
// never goes backwards, so he was a contractor, not an officer. And the grange
// sold the same thing he did. So the grange's +20% to every shed became his,
// building up over his service and lost when he is paid off.
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:ports_ahoy/sim/retinue.dart';
import 'package:ports_ahoy/ui/growth_text.dart';

Retainer reeve(int level) => retainerAt(RetinueTrack.reeve, level)!;

/// A new port with coin to spare and a farm, so the reeve can be hired.
GameState withFarm() {
  final g = GameState.newGame();
  g.coin = 50000;
  g.buildings.add(Building(defId: 'farm', workers: 2));
  g.placeAll();
  return g;
}

/// Run the port for [n] days with coin and food kept topped up, so neither
/// wages nor the reeve's appetite becomes the story of a test about something
/// else.
void days(GameState g, double n) {
  for (var i = 0; i < n * Balance.ticksPerDay; i++) {
    g.coin = 50000;
    g.stock[Resource.fish] = g.storageCapacity;
    g.step();
  }
}

void main() {
  test('he is offered once a farm stands, and not before', () {
    final g = GameState.newGame();
    g.coin = 50000;
    expect(g.buildings.any((b) => b.defId == 'farm'), isFalse);
    expect(g.canHire(reeve(1)), isFalse,
        reason: 'where the grange used to unlock: behind a farm');
    g.buildings.add(Building(defId: 'farm', workers: 2));
    g.placeAll();
    expect(g.canHire(reeve(1)), isTrue);
  });

  test('his bonus builds up over his service and survives a promotion', () {
    final g = withFarm();
    expect(g.reeveYieldBonus, 1.0);
    g.hire(reeve(1));
    expect(g.reeveService, 0, reason: 'he starts from nothing');

    days(g, Balance.reeveServiceDays / 2);
    expect(g.reeveService, closeTo(0.5, 0.01));
    expect(g.reeveYieldBonus, closeTo(1 + reeve(1).yieldBonus * 0.5, 0.005));

    // Promotion is the same man paid better: the order he has made stays.
    g.hire(reeve(2));
    expect(g.reeveService, closeTo(0.5, 0.01));
    expect(g.reeveYieldBonus, closeTo(1 + reeve(2).yieldBonus * 0.5, 0.005));

    days(g, Balance.reeveServiceDays / 2 + 1);
    expect(g.reeveService, 1.0);
    expect(g.reeveYieldBonus, closeTo(1 + reeve(2).yieldBonus, 1e-9));
  });

  test('paying him off throws his work away, so he is not a contractor', () {
    final g = withFarm();
    g.hire(reeve(1));
    days(g, Balance.reeveServiceDays + 1);
    expect(g.reeveYieldBonus, closeTo(1 + reeve(1).yieldBonus, 1e-9));

    g.dismiss(RetinueTrack.reeve);
    expect(g.reeveService, 0);
    expect(g.reeveYieldBonus, 1.0);

    // And a fresh hire starts again from nothing, so hire-fire-rehire buys
    // nothing back.
    g.hire(reeve(1));
    expect(g.reeveService, 0);
  });

  test('his bonus reaches the output of every shed', () {
    // Two identical ports, one with a reeve who has the land in order.
    final plain = withFarm();
    final kept = withFarm();
    kept.hire(reeve(1));
    kept.reeveService = 1;
    kept.coin = plain.coin;
    expect(kept.husbandryBonus, closeTo(1 + reeve(1).yieldBonus, 1e-9));

    plain.step();
    kept.step();
    Building camp(GameState g) =>
        g.buildings.firstWhere((b) => b.defId == 'forest_camp');
    final a = camp(plain).hold[Resource.timber] ?? 0;
    final b = camp(kept).hold[Resource.timber] ?? 0;
    expect(a, greaterThan(0));
    expect(b / a, closeTo(1 + reeve(1).yieldBonus, 0.001));
  });

  test('a grange from an old run and a reeve take the better, never both', () {
    final g = withFarm();
    g.buildings.add(Building(defId: 'grange', workers: 2)..maturity = 1);
    g.placeAll();
    expect(g.husbandryBonus, closeTo(1 + Balance.grangeMaxYield, 1e-9));

    g.hire(reeve(1));
    g.reeveService = 1; // +15%, under the grange's +20%
    expect(g.husbandryBonus, closeTo(1 + Balance.grangeMaxYield, 1e-9),
        reason: 'stacking would give an old run a bonus no new one can reach');

    g.hire(reeve(2));
    g.hire(reeve(3));
    expect(g.husbandryBonus, closeTo(1 + reeve(3).yieldBonus, 1e-9));
  });

  test('an old save keeps its grange working, and his service survives', () {
    final g = withFarm();
    g.buildings.add(Building(defId: 'grange', workers: 2)..maturity = 1);
    g.placeAll();
    g.hire(reeve(1));
    g.reeveService = 0.4;

    final back = GameState.fromJson(g.toJson());
    final grange = back.buildings.firstWhere((b) => b.defId == 'grange');
    expect(grange.maturity, 1.0);
    expect(back.husbandryBonus, closeTo(1 + Balance.grangeMaxYield, 1e-9));
    expect(back.reeveLevel, 1);
    expect(back.reeveService, closeTo(0.4, 1e-3));

    // A save from before he had a service starts him from the load.
    final old = g.toJson()..remove('reeveService');
    expect(GameState.fromJson(old).reeveService, 0);
  });

  group('his appetite', () {
    test('he eats after the town, and goes hungry rather than cost a family',
        () {
      // "Cost more food than a regular villager" — the reeve's running cost.
      final g = withFarm();
      g.hire(reeve(1));
      g.reeveService = 1;
      g.population = 10;
      for (final r in Resource.values.where((r) => r.isFood)) {
        g.stock[r] = 0;
      }
      // Enough for the town for one day, and not a mouthful more.
      g.stock[Resource.fish] = 10 * Balance.foodPerPersonPerDay;
      final people = g.population;
      for (var i = 0; i < Balance.ticksPerDay; i++) {
        g.coin = 50000;
        g.step();
      }
      expect(g.population, people, reason: 'the town ate first');
      expect(g.reeveHungry, isTrue);
      expect(g.reeveYieldBonus, 1.0,
          reason: 'a hungry reeve does nothing — the unfed pet\'s rule');

      // Feed the stores and he is back at work.
      days(g, 1);
      expect(g.reeveHungry, isFalse);
      expect(g.reeveYieldBonus, closeTo(1 + reeve(1).yieldBonus, 1e-9));
    });

    test('a hungry reeve makes no progress', () {
      final g = withFarm();
      g.hire(reeve(1));
      g.reeveService = 0.3;
      g.reeveHungry = true;
      for (var i = 0; i < Balance.ticksPerDay ~/ 2; i++) {
        g.coin = 50000;
        g.step();
      }
      expect(g.reeveService, 0.3,
          reason: 'the half-day before the next meal, his build-up waits');
    });

    test('the food days count his mouths', () {
      final g = withFarm();
      final before = g.foodDays;
      g.hire(reeve(1));
      final pop = g.population;
      expect(g.foodDays,
          closeTo(before * pop / (pop + reeve(1).appetite), 1e-9));
    });

    test('each rank eats more, as each does more', () {
      for (var lvl = 2; lvl <= 3; lvl++) {
        expect(reeve(lvl).appetite, greaterThan(reeve(lvl - 1).appetite));
      }
      expect(reeve(1).appetite, 5);
    });
  });

  group('what the game says about him', () {
    test('a growing shed counts his speed, and names it', () {
      // The shed bubble used to work out its own countdown and leave him
      // out: hire him and every growing shed quoted the same days as before.
      final g = withFarm();
      final pasture = Building(defId: 'pasture', workers: 2)..maturity = 0.5;
      g.buildings.add(pasture);
      g.placeAll();

      final before = shedGrowthLine(g, pasture)!;
      expect(before, contains('full in about 15 days'));
      expect(before, isNot(contains('reeve')));

      g.hire(reeve(1)); // x1.25: fifteen days become twelve
      final after = shedGrowthLine(g, pasture)!;
      expect(after, contains('full in about 12 days'));
      expect(after, contains('3 days sooner for your reeve'));
    });

    test('his card says how far along he is and what it would cost to lose',
        () {
      final g = withFarm();
      g.hire(reeve(1));
      days(g, 4);
      final lines = reeveAtWorkLines(g, reeve(1));
      expect(lines.first, contains('Getting the land in order'));
      expect(lines.first, contains('goes with him'));

      g.reeveService = 1;
      expect(reeveAtWorkLines(g, reeve(1)).first,
          'The land is in order: every shed +15%. He eats like 5 villagers.');

      g.reeveHungry = true;
      expect(reeveAtWorkLines(g, reeve(1)).first, startsWith('Hungry'),
          reason: 'a reeve doing nothing has to say why');
    });

    test('the offer states the bonus and the wait before you pay', () {
      final g = withFarm();
      final line = reeveOfferLine(g, reeve(1));
      expect(line, contains('Every shed +15%'));
      expect(line, contains('eating like 5 villagers'),
          reason: 'the running cost, before the player pays');
      expect(line, contains('${Balance.reeveServiceDays.round()} days'));
    });
  });
}
