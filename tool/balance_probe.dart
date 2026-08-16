// ignore_for_file: avoid_print — this is a command-line instrument; stdout is
// its entire user interface.

// Headless pacing check: plays the port with a competent-but-not-optimal
// policy and reports how the economy trends. Run with:
//
//   dart run tool/balance_probe.dart
//
// This is a tuning instrument, not a test. It answers "is the game winnable,
// and does it take an interesting number of days?" — the question a balance
// spreadsheet is normally used for, except it runs the real simulation.

import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/events.dart';
import 'package:ports_ahoy/sim/charters.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:ports_ahoy/sim/trade.dart';

/// What the policy builds, in order, whenever it can afford the next item.
const List<String> buildOrder = [
  'forest_camp', 'sawmill', 'house', 'flax_field', 'ropewalk',
  'warehouse', 'farm', 'flax_field', 'weaver', 'house',
  'mine', 'sawmill', 'smithy', 'warehouse', 'house',
  'import_berth', 'forest_camp', 'cooperage', 'mine', 'smithy',
  'house', 'import_berth', 'flax_field', 'weaver', 'warehouse',
  'farm', 'house', 'import_berth', 'sawmill', 'house',
];

/// Stock levels the policy aims to keep of each importable, used to decide
/// which cargo each berth puts its standing order on.
const Map<Resource, double> importTargets = {
  Resource.timber: 220,
  Resource.flax: 160,
  Resource.ore: 130,
};

/// Coin above which the policy considers itself rich enough to staff a berth.
const int importCoinThreshold = 4000;

/// Never sell these below the reserve — food feeds the town, planks build it,
/// and the lighthouse wants 80 tools banked before it will light.
const Map<Resource, double> reserves = {
  Resource.fish: 60,
  Resource.grain: 60,
  Resource.planks: 190,
  Resource.tools: 95,
  Resource.rope: 135,
  Resource.sailcloth: 105,
};

/// Stock the policy will pay a markup for when a ship happens to carry it.
const Map<Resource, double> buyTargets = {
  Resource.planks: 200,
  Resource.timber: 120,
  Resource.ore: 90,
  Resource.flax: 110,
};

const int maxDays = 400;

/// Outcome of one full playthrough.
class Run {
  Run(this.seed, this.winDay, this.peakCoin, this.endPopulation,
      this.endBuildings, this.shortfall, this.hazards, this.boons);
  final int seed;

  /// Day the lighthouse was lit, or -1 if the run never got there.
  final int winDay;
  final int peakCoin;
  final int endPopulation;
  final int endBuildings;

  /// For a run that never won: which requirements were unmet, and by how much.
  /// This is the difference between "the game is too hard" and "the game is
  /// unwinnable from this seed", which the win/loss flag alone cannot tell you.
  final Map<String, double> shortfall;

  /// How much weather the run actually saw.
  final int hazards;
  final int boons;

  bool get won => winDay > 0;
}

Map<String, double> _shortfallOf(GameState g) {
  final short = <String, double>{};
  if (g.coin < Balance.lighthouseCoin) {
    short['coin'] = (Balance.lighthouseCoin - g.coin).toDouble();
  }
  Balance.lighthouseCost.forEach((r, need) {
    final have = g.stock[r];
    if (have < need) short[r.label.toLowerCase()] = need - have;
  });
  return short;
}

/// Seeds are fixed rather than random so a tuning change can be compared
/// against the previous run honestly, instead of against different weather.
const List<int> seeds = [12345, 777, 20260815, 31415, 8675309, 4242, 99, 1618];

/// The charters in force for this sweep, from `--charters=id1,id2`.
///
/// Added because a hardship was reported from play as changing nothing you
/// could feel. A charter whose effect cannot be measured against the same eight
/// seeds is a charter that is not really there.
CharterSet _charters = CharterSet.none;

void main(List<String> args) {
  final arg = args.firstWhere((a) => a.startsWith('--charters='),
      orElse: () => '');
  if (arg.isNotEmpty) {
    final ids = arg.substring('--charters='.length).split(',')
      ..removeWhere((s) => s.isEmpty);
    for (final id in ids) {
      if (charterById(id) == null) {
        final known = kCharters.map((c) => c.id).join(', ');
        print('No such charter: $id');
        print('Known: $known');
        return;
      }
    }
    _charters = CharterSet.fromIds(ids);
    final held = _charters.ids.join(', ');
    print('Charters in force: $held  (difficulty ${_charters.difficulty})');
  }

  final verboseSeed = seeds.first;
  final runs = <Run>[];

  for (final seed in seeds) {
    runs.add(_play(seed, verbose: seed == verboseSeed));
  }

  _summarise(runs);
}

void _summarise(List<Run> runs) {
  final won = runs.where((r) => r.won).toList();
  final winDays = won.map((r) => r.winDay).toList()..sort();
  final peaks = runs.map((r) => r.peakCoin).toList()..sort();

  print('');
  print('=' * 62);
  print('${runs.length} seeds · ${won.length} completed the lighthouse');

  if (winDays.isNotEmpty) {
    final median = winDays[winDays.length ~/ 2];
    final spread = winDays.last - winDays.first;
    print('win day   min ${winDays.first}  median $median  max ${winDays.last}'
        '  (spread $spread days)');
  }
  if (peaks.isNotEmpty) {
    print('peak coin min ${peaks.first}  median ${peaks[peaks.length ~/ 2]}'
        '  max ${peaks.last}');
    final ratio = peaks[peaks.length ~/ 2] / Balance.lighthouseCoin;
    print('median peak coin is ${ratio.toStringAsFixed(1)}x the '
        '${Balance.lighthouseCoin}c requirement '
        '${ratio > 2.5 ? "— coin is still too loose" : "— coin stays relevant"}');
  }

  final hz = runs.map((r) => r.hazards).toList()..sort();
  final bn = runs.map((r) => r.boons).toList()..sort();
  print('weather   hazards median ${hz[hz.length ~/ 2]} (min ${hz.first} max ${hz.last})'
      '  ·  boons median ${bn[bn.length ~/ 2]}');

  for (final r in runs.where((r) => !r.won)) {
    final missing = r.shortfall.entries
        .map((e) => '${e.key} short by ${e.value.round()}')
        .join(', ');
    print('  seed ${r.seed}: NO WIN in $maxDays days '
        '(pop ${r.endPopulation}, ${r.endBuildings} buildings) — $missing');
  }
  print('=' * 62);
}

Run _play(int seed, {bool verbose = false}) {
  final g = GameState.newGame(seed: seed, charters: _charters);
  var buildIndex = 0;
  var peakCoin = 0;
  var lighthouseDay = -1;
  var hazards = 0;
  var boons = 0;
  final seenEvents = <ActiveEvent>{};

  if (verbose) print('--- seed $seed (detailed) ---');

  for (var day = 1; day <= maxDays; day++) {
    for (var h = 0; h < Balance.ticksPerDay; h++) {
      g.step();
      // Sheds fill their own yards now; an attentive player empties them.
      g.collectAll();
      for (final e in g.events.live(g.tick)) {
        if (seenEvents.add(e)) {
          if (e.def.isHazard) {
            hazards++;
          } else {
            boons++;
          }
        }
      }
      _sellEverythingOffered(g);
      _buyWhatWeLack(g);
    }

    _sendConsignments(g);
    buildIndex = _tryBuild(g, buildIndex);
    _reassign(g);

    if (g.coin > peakCoin) peakCoin = g.coin;

    if (lighthouseDay < 0 && g.canBuildLighthouse) {
      lighthouseDay = day;
      g.buildLighthouse();
    }

    if (verbose && (day % 25 == 0 || day == 1)) _report(g, day, buildIndex);
    if (lighthouseDay > 0) break;
  }

  if (verbose) {
    print(lighthouseDay > 0
        ? 'seed $seed: lighthouse lit on day $lighthouseDay'
        : 'seed $seed: no win in $maxDays days');
  }

  return Run(seed, lighthouseDay, peakCoin, g.population, g.buildings.length,
      lighthouseDay > 0 ? const {} : _shortfallOf(g), hazards, boons);
}

void _report(GameState g, int day, int buildIndex) {
  final sheds = <String, int>{};
  for (final b in g.buildings) {
    sheds[b.def.name] = (sheds[b.def.name] ?? 0) + 1;
  }
  final tools = g.stock[Resource.tools].round();
  final planks = g.stock[Resource.planks].round();
  print('day ${day.toString().padLeft(3)} | '
      'coin ${g.coin.toString().padLeft(5)} | '
      'pop ${g.population.toString().padLeft(2)}/${g.housingCapacity} | '
      'food ${g.foodDays.isFinite ? g.foodDays.toStringAsFixed(1) : "inf"}d | '
      'planks ${planks.toString().padLeft(3)} | '
      'tools ${tools.toString().padLeft(3)} | '
      'built ${g.buildings.length}');
}

/// Dump anything a ship will take, above the reserves.
void _sellEverythingOffered(GameState g) {
  for (final ship in List.of(g.market.ships)) {
    for (final offer in ship.offers.where((o) => !o.isFilled)) {
      final reserve = reserves[offer.resource] ?? 0;
      final spare = g.stock[offer.resource] - reserve;
      if (spare >= 1) g.sell(ship, offer, spare);
    }
  }
}

/// Ship surplus abroad, to the port that pays best per day of crossing.
///
/// THE BOT DID NOT DO THIS FOR MOST OF THE PROJECT, and the omission gave two
/// wrong readings in a row: an A/B of the first merchant showed no effect at
/// all (they earn most of their keep on consignments), and the Distant Waters
/// charter — which does nothing BUT lengthen crossings — measured as exactly
/// zero difficulty. A probe that never sails cannot price anything to do with
/// sailing.
///
/// Deliberately simple: hold back the same reserves as the quay policy, fill a
/// hull with whatever is spare, and pick the destination paying the best rate
/// per day. A human would do better; this only has to be non-zero and
/// consistent between runs.
void _sendConsignments(GameState g) {
  while (g.canSendVoyage) {
    final cargo = <Resource, double>{};
    for (final r in Resource.values) {
      // Finished goods only. Shipping food starves the town while the hull is
      // away, and shipping raws exports the very inputs the workshops are
      // waiting on — the first version of this did both and cost six of eight
      // seeds their win. A consignment is surplus leaving, not supply.
      if (r.category != ResourceCategory.good) continue;
      final spare = g.stock[r] - (reserves[r] ?? 0);
      if (spare >= 20) cargo[r] = spare;
    }
    if (cargo.isEmpty) return;

    Destination? best;
    var bestRate = 0.0;
    for (final d in kDestinations) {
      final crossing = g.daysBreakdown(d);
      if (crossing.days <= 0) continue;
      final rate = g.quoteVoyage(d, cargo) / crossing.days;
      if (rate > bestRate) {
        bestRate = rate;
        best = d;
      }
    }
    if (best == null || bestRate <= 0) return;
    if (!g.sendVoyage(best, cargo)) return;
  }
}

/// Spend surplus coin restocking chains that have run dry.
void _buyWhatWeLack(GameState g) {
  for (final ship in List.of(g.market.ships)) {
    for (final ware in ship.wares.where((w) => !w.isFilled)) {
      final target = buyTargets[ware.resource];
      if (target == null) continue;
      if (g.coin < g.dailyWageBill * 5) return;
      final short = target - g.stock[ware.resource];
      if (short >= 1) g.buy(ship, ware, short);
    }
  }
}

int _tryBuild(GameState g, int index) {
  while (index < buildOrder.length) {
    final def = defById(buildOrder[index]);
    // Keep a coin cushion so wages never go unpaid on the next day.
    if (g.coin - def.coinCost < g.dailyWageBill * 3) return index;
    // Not unlocked yet: wait for it rather than skipping down the order, so
    // the probe experiences the tree the way a player does.
    if (!g.isUnlocked(def.id)) return index;
    if (!g.build(def)) return index;
    index++;
  }
  return index;
}

/// Rebuild the whole labour allocation each morning: feed the town first,
/// then staff by margin, skipping workshops that have no input to chew on.
void _reassign(GameState g) {
  for (final b in g.buildings) {
    b.workers = 0;
  }

  final foodNeed = g.population * Balance.foodPerPersonPerDay / Balance.ticksPerDay;
  var foodRate = 0.0;

  // 1. Cover the day's eating, with headroom for growth.
  for (var i = 0; i < g.buildings.length && foodRate < foodNeed * 1.4; i++) {
    final def = g.buildings[i].def;
    final out = def.outputs.entries
        .where((e) => e.key.isFood)
        .fold(0.0, (s, e) => s + e.value);
    if (out <= 0) continue;
    while (g.buildings[i].workers < def.maxWorkers &&
        g.idleWorkers > 0 &&
        foodRate < foodNeed * 1.4) {
      g.setWorkers(i, g.buildings[i].workers + 1);
      foodRate += out;
    }
  }

  // 1b. Point each berth at a different shortage, so import pressure spreads
  // across the three cargoes instead of walking one price into the ceiling.
  final byNeed = [...kImportables]..sort((a, b) {
      final ra = g.stock[a] / (importTargets[a] ?? 100);
      final rb = g.stock[b] / (importTargets[b] ?? 100);
      return ra.compareTo(rb);
    });
  var berthIndex = 0;
  for (var i = 0; i < g.buildings.length; i++) {
    final def = g.buildings[i].def;
    if (!def.imports) continue;
    g.buildings[i].importResource = byNeed[berthIndex % byNeed.length];
    berthIndex++;
    // Coin is only worth anything once it is cargo — until the sheds have
    // banked every material the lighthouse wants, at which point the last
    // thing standing between you and the light is coin, so stop importing.
    final stillShort =
        Balance.lighthouseCost.entries.any((e) => g.stock[e.key] < e.value);
    if (g.coin > importCoinThreshold && stillShort) {
      while (g.buildings[i].workers < def.maxWorkers && g.idleWorkers > 0) {
        g.setWorkers(i, g.buildings[i].workers + 1);
      }
    }
  }

  // 2. Everyone else goes to the richest shed that actually has input.
  final order = List.generate(g.buildings.length, (i) => i)
      .where((i) => g.buildings[i].def.isProducer)
      .toList()
    ..sort((a, b) => g.buildings[b].def.marginPerWorkerTick
        .compareTo(g.buildings[a].def.marginPerWorkerTick));

  for (final i in order) {
    final def = g.buildings[i].def;
    final starved = def.inputs.keys.any((r) => g.stock[r] < 10);
    if (starved) continue;
    while (g.buildings[i].workers < def.maxWorkers && g.idleWorkers > 0) {
      g.setWorkers(i, g.buildings[i].workers + 1);
    }
  }

  // 3. Any hand still spare goes to raw extraction to refill the chains.
  for (final i in order) {
    final def = g.buildings[i].def;
    if (def.isWorkshop) continue;
    while (g.buildings[i].workers < def.maxWorkers && g.idleWorkers > 0) {
      g.setWorkers(i, g.buildings[i].workers + 1);
    }
  }
}
