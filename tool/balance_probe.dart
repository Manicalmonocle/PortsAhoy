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

import 'dart:io';

import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/events.dart';
import 'package:ports_ahoy/sim/charters.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:ports_ahoy/sim/retinue.dart';
import 'package:ports_ahoy/sim/run_code.dart';
import 'package:ports_ahoy/sim/trade.dart';
import 'package:ports_ahoy/version.dart';

/// What the policy builds, in order, whenever it can afford the next item.
const List<String> buildOrder = [
  'forest_camp', 'sawmill', 'house', 'flax_field', 'ropewalk',
  'warehouse', 'farm', 'flax_field', 'weaver', 'house',
  'mine', 'sawmill', 'smithy', 'warehouse', 'house',
  'import_berth', 'forest_camp', 'cooperage', 'mine', 'smithy',
  'house', 'import_berth', 'flax_field', 'weaver', 'warehouse',
  'farm', 'house', 'import_berth', 'sawmill', 'house',
];

/// The same port, but committing hands to the dark trade instead of a second
/// smithy and weaver.
///
/// Exists to answer a player's verdict with a measurement rather than an
/// opinion: "I skip it because it doesn't feel worth the investment... just
/// adds another layer for no real payoff." A layer that cannot be shown to pay
/// for the hands it takes is one of two things, and only a run tells you which.
const List<String> darkBuildOrder = [
  // Identical to the honest order through the first smithy — a port that never
  // builds one cannot make the 80 tools the light needs, and an order that
  // buries it measures nothing but the ordering mistake. The dark sheds take
  // the place of the SECOND smithy and weaver, which is the real trade a
  // player makes: these hands, or those.
  'forest_camp', 'sawmill', 'house', 'flax_field', 'ropewalk',
  'warehouse', 'farm', 'flax_field', 'weaver', 'house',
  'mine', 'sawmill', 'smithy', 'warehouse', 'house',
  // COOPERAGE BEFORE DISTILLERY, and it is not optional: a distillery costs 10
  // barrels and barrels come from nowhere else. Without it the queue stopped
  // dead at the distillery forever — 20 sheds, 25 people and 47,000 coin at
  // day 400, having never built a single dark shed. Every "the dark trade
  // loses 8 of 8" figure measured before this was a stalled honest port, not
  // the dark trade.
  'import_berth', 'cooperage', 'distillery', 'mine', 'bonded_cellar',
  // The berth is the whole point of the chain and was missing: without it the
  // port makes powder it can only sell, never boards a hull, and never sees a
  // grain of spice. A "dark" run that cannot take a prize was measuring the
  // contraband sheds alone, which is exactly the losing half.
  'house', 'privateer_berth', 'powder_mill', 'import_berth', 'warehouse',
  'farm', 'house', 'import_berth', 'sawmill', 'house',
];

/// True when `--dark` was passed: build the contraband chain and trade it.
bool kDark = false;

/// Powder kept back for boarding rather than sold as cargo.
const double darkPowderReserve = 60;

int kPrizesTaken = 0;
int kPrizeBlocked = 0;
int kSpiceDealsSeen = 0;
int kSpiceDealsTaken = 0;

/// True when `--hire` was passed: take on officers.
///
/// OFF BY DEFAULT, AND THAT IS A FINDING RATHER THAN AN OMISSION. The player
/// this bot is calibrated against hired four times and won on day 93, so the
/// obvious correction was to make the bot hire too. Measured against their
/// curve, it made the match twice as bad:
///
///     no hiring : combined error 30.1%, median win day 126
///     hiring    : combined error 45.8%, median win day 168
///
/// The bot reproduces the player's hiring MILESTONES almost exactly — first
/// hire day 2 against their day 3, four hires against their four — and still
/// gets further from their curve, because officer wages are permanent and the
/// bot's coin is still ~60% short of what that player was earning. Hiring is
/// not what a strong economy buys; it is what a strong economy can afford. The
/// income gap has to close before this can be turned on honestly.
///
/// Kept behind a flag so the experiment is one command away rather than
/// something to write again from scratch:  --hire
bool kHire = false;

/// Where to write the first seed's run as a PA1 code, if `--journal=` is given.
///
/// The bot plays a real GameState, so it has been keeping a journal all along
/// and simply never handed it over. Emitting it in the same format a player's
/// phone sends means one comparison tool works on both, and "the bot plays
/// like a human" becomes a measurement instead of a claim.
String? kJournalPath;

/// Stock levels the policy aims to keep of each importable, used to decide
/// which cargo each berth puts its standing order on.
const Map<Resource, double> importTargets = {
  Resource.timber: 220,
  Resource.flax: 160,
  Resource.ore: 130,
};

/// Coin above which the policy considers itself rich enough to staff a berth.
const int importCoinThreshold = 4000;

/// What the policy keeps back, EARLY: enough to eat and to keep building.
///
/// The old policy held a flat reserve of planks 190, tools 95, rope 135 and
/// sailcloth 105 for the whole run — which is the lighthouse's bill of
/// materials plus a margin. It was therefore banking the entire win condition
/// from day one, and `spare = stock - reserve` never went positive, so it could
/// not sell a plank or ship a consignment for the first hundred days. Measured
/// against a real player: the bot's first consignment left on day 139 of a
/// 149-day run, against their day 13, and it sailed 4 times against their 11.
/// Its income was strangled by its own savings plan.
///
/// A person does not play that way. They sell and ship freely while the light
/// is far off, and bank the materials once it is in sight — because a working
/// port can re-make 160 planks in a few days, and coin earned early compounds
/// into sheds, hands and more coin.
const Map<Resource, double> workingReserve = {
  Resource.fish: 25,
  Resource.grain: 25,
  Resource.planks: 40,
};

/// Margin over the lighthouse's exact bill, so a late sale cannot shave the
/// win out from under a run that had it.
const double endgameMargin = 1.15;

/// Buildings after which the port stops expanding and starts finishing.
///
/// A person decides at some point that the port is big enough and turns to the
/// light. The bot had no such moment: it worked down a thirty-item build order
/// forever. Keyed on sheds standing rather than on coin, because a coin-keyed
/// trigger deadlocks — coin stays low, so the reserve stays low, so it keeps
/// selling the very materials it needs, so coin stays low. Measured: 0 of 8
/// seeds won that way, all of them ending on 40 population and 33 buildings
/// with no light. The player this is calibrated against won on 25 buildings.
const int expandUntil = 25;

/// And enough hands to actually work them.
///
/// Shed count alone was not enough: on one seed the port hit 25 sheds with only
/// 24 people, stopped expanding, and could never make the 160 planks the light
/// needed — it failed with `planks short by 160` while sitting on a build order
/// it had chosen to stop reading. A port that is behind should keep growing,
/// and population is the honest measure of whether the sheds standing are sheds
/// working.
const int expandAtPopulation = 32;

bool inEndgame(GameState g) =>
    g.buildings.length >= expandUntil && g.population >= expandAtPopulation;

/// What the policy keeps back right now.
///
/// Two regimes, not a slide. While the port is still growing it holds only
/// enough to eat and to build, and everything else is income. Once it turns to
/// finishing it holds the lighthouse's whole bill, because a sale that shaves
/// the win out from under a finished run is the one mistake worth being
/// completely rigid about.
/// How far down the build order the policy has got. Kept where the selling
/// policy can see it, because what you must not sell depends on what you are
/// about to build.
int kBuildIndex = 0;

Map<Resource, double> reservesNow(GameState g) {
  final out = <Resource, double>{...workingReserve};

  // NEVER SELL THE NEXT BUILDING.
  //
  // The flat plank floor of 40 was below the cost of the next shed, so the
  // quay stripped the yard to 40 every tick and the queue could never afford
  // anything again. Measured: a port stuck on 20 buildings and 25 people from
  // day 100 to day 400 while its coin climbed to 28,000 — rich, capped, and
  // unable to lay a single plank. The honest order survived this by luck; the
  // dark one, which needs a house at exactly the wrong moment, did not.
  final order = kDark ? darkBuildOrder : buildOrder;
  if (kBuildIndex < order.length) {
    defById(order[kBuildIndex]).cost.forEach((r, need) {
      final keep = need * 1.2;
      final current = out[r] ?? 0;
      out[r] = keep > current ? keep : current;
    });
  }

  if (!inEndgame(g)) return out;
  g.lighthouseGoodsCost.forEach((r, need) {
    final banked = need * endgameMargin;
    final current = out[r] ?? 0;
    out[r] = banked > current ? banked : current;
  });
  return out;
}

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

  kHire = args.contains('--hire');
  if (kHire) print('Retinue: hiring officers up to rank $topRank.');

  kDark = args.contains('--dark');
  if (kDark) print('Dark trade: building and working the contraband chain.');

  final journalArg = args.firstWhere((a) => a.startsWith('--journal='),
      orElse: () => '');
  if (journalArg.isNotEmpty) {
    kJournalPath = journalArg.substring('--journal='.length);
  }

  final verboseSeed = seeds.first;
  final runs = <Run>[];

  for (final seed in seeds) {
    runs.add(_play(seed, verbose: seed == verboseSeed));
  }

  _summarise(runs);
  if (kDark) {
    print('prizes taken $kPrizesTaken · blocked $kPrizeBlocked · '
        'spice deals seen $kSpiceDealsSeen · taken $kSpiceDealsTaken');
  }
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
      if (kDark) _workTheDarkTrade(g);
    }

    _sendConsignments(g);
    if (kHire) _hireRetinue(g);
    buildIndex = _tryBuild(g, buildIndex);
    kBuildIndex = buildIndex;
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

    final path = kJournalPath;
    if (path != null) {
      File(path).writeAsStringSync(RunCode.encode(
        g.journal,
        version: 'bot-$kAppVersion',
        seed: seed,
        difficulty: _charters.difficulty,
        charters: _charters.ids.toList(),
        won: lighthouseDay > 0,
        // No URL to fit inside here, so keep every day.
        maxChars: 1 << 30,
      ));
      print('journal written to $path');
    }
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
  final reserves = reservesNow(g);
  for (final ship in List.of(g.market.ships)) {
    for (final offer in ship.offers.where((o) => !o.isFilled)) {
      final reserve = reserves[offer.resource] ?? 0;
      final spare = g.stock[offer.resource] - reserve;
      if (spare >= 1) g.sell(ship, offer, spare);
    }
  }
}

/// Move contraband the way the design intends it to be moved.
///
/// Barter first — swapping contraband for bulk raws is the channel the dark
/// trade exists for, and pays far better than coin — then sell whatever a free
/// trader will bid on. Nothing is hoarded: holding contraband is what the
/// Revenue seizes and what rivals raid, so a policy that sits on it would be
/// measuring a mistake rather than the mechanic.
void _workTheDarkTrade(GameState g) {
  // Take every lawful prize on offer. Spice cannot be made, imported or
  // bought, so a hull at the quay is the only place it comes from — and the
  // powder spent is the cheapest thing the chain produces.
  for (final ship in List.of(g.market.ships)) {
    if (g.prizeBlocker(ship) != null) {
      if (ship.foreign && ship.prizeTons > 0) kPrizeBlocked++;
      continue;
    }
    if (g.prizeSuccessChance(ship) < 0.5) continue; // don't feed the sea
    if (g.takePrize(ship)) kPrizesTaken++;
  }

  for (final ship in List.of(g.market.ships)) {
    if (!ship.isFreeTrader) continue;
    for (final deal in List.of(ship.barters)) {
      if (deal.give == Resource.powder &&
          g.stock[Resource.powder] - deal.giveQty < darkPowderReserve) {
        continue;
      }
      if (deal.give == Resource.spice) kSpiceDealsSeen++;
      if (g.stock[deal.give] >= deal.giveQty) {
        if (deal.give == Resource.spice) kSpiceDealsTaken++;
        g.barter(ship, deal);
      }
    }
    for (final offer in ship.offers.where((o) => !o.isFilled)) {
      if (!offer.resource.isContraband) continue;
      // Powder is ammunition before it is cargo. Selling it all is why the
      // port boarded 3 hulls in eight runs and was blocked 5,897 times for
      // want of a charge — and with no prizes there is no spice, so the whole
      // chain paid for itself in nothing.
      if (offer.resource == Resource.powder &&
          g.stock[Resource.powder] <= darkPowderReserve) {
        continue;
      }
      // Spice is never sold. It is the only currency that buys finished work,
      // and coin is the thing this port already has too much of.
      if (offer.resource == Resource.spice) continue;
      final held = g.stock[offer.resource];
      if (held >= 1) g.sell(ship, offer, held);
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
  final reserves = reservesNow(g);
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

/// Take on officers, the way the player this is calibrated against did.
///
/// The bot hired NOTHING for the entire life of this project, while the real
/// run it is measured against hired on day 3 — a captain, for 450 coin, out of
/// the 980 that a_full_purse starts you with — and four times over 93 days.
/// Every crossing after that day was shorter, which compounds: a consignment
/// policy and a captain are the same lever pulled twice.
///
/// Captain before quartermaster because that is the order the player used and
/// because shorter crossings pay back immediately, where reduced waste pays
/// back in proportion to a throughput the port does not have yet. The merchant
/// is deliberately last: that same player skipped it entirely across a whole
/// run, so buying it eagerly here would model nobody.
/// The highest rank the policy will buy.
///
/// Third-rank officers cost 5,200 and 6,600 coin — together more than the
/// 9,000 the lighthouse itself asks for. Measured: buying them pushed the bot
/// from a median 126-day win out to 184, because it spent the light's own coin
/// on rank and then had to earn it twice. The player being modelled took both
/// tracks to rank two and stopped, which on this evidence was correct.
///
/// This is a statement about how people play, not a claim that rank three is
/// mispriced — a longer game than the lighthouse might well justify it.
const int topRank = 2;

void _hireRetinue(GameState g) {
  const order = [
    RetinueTrack.captain,
    RetinueTrack.quartermaster,
    RetinueTrack.merchant,
  ];
  for (final track in order) {
    final next = g.nextOn(track);
    if (next == null) continue;
    if (next.level > topRank) continue;
    if (!g.canHire(next)) continue;
    // Wages are forever and the coin is gone today, so leave enough behind to
    // keep the port fed and building rather than buying rank it cannot carry.
    if (g.coin - next.coinCost < g.dailyWageBill * 6) continue;
    if (g.hire(next)) return; // one promotion a day, never a spree
  }
}

int _tryBuild(GameState g, int index) {
  // Once the port turns to finishing, coin is for the light and not for the
  // next shed. The first version of this said `&& coin < lighthouseCoinCost`,
  // which let the port start building again the very moment it could afford
  // the light — spending the exact coin it had just banked. It never won: the
  // trace shows it oscillating between 800 and 3,600 coin for two hundred days
  // with 33 sheds standing. Stopping means stopping.

  if (inEndgame(g)) return index;

  final order = kDark ? darkBuildOrder : buildOrder;
  while (index < order.length) {
    final def = defById(order[index]);
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

  // 1b. Crew the privateer berth, in dark runs only.
  //
  // The general allocation below ranks sheds by marginPerWorkerTick, and a
  // berth produces nothing — so it scored zero and was never staffed. The port
  // built the whole chain, made the powder, and then had no crew to board
  // anybody with. Prizes are the only source of spice, so this one omission
  // was the difference between measuring the dark trade and measuring a
  // distillery.
  if (kDark) {
    for (var i = 0; i < g.buildings.length; i++) {
      if (g.buildings[i].defId != 'privateer_berth') continue;
      final def = g.buildings[i].def;
      while (g.buildings[i].workers < def.maxWorkers && g.idleWorkers > 1) {
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
