/// Trade you start, rather than trade that arrives and waits to be answered.
///
/// Two ways to take the initiative:
///   * the **chandler**, who will sell you raw stock on demand at a markup, so
///     a shortage is something you can fix now instead of hoping a ship turns
///     up carrying it;
///   * **voyages**, where you load your own cargo and send it to a port that
///     actually wants it, instead of dumping it on the local quay and watching
///     the price collapse.
///
/// ON THE DURATION OF A VOYAGE. A voyage takes days, which is the first thing
/// in this codebase that does. The rule it must satisfy is unchanged in spirit
/// and stated plainly: **nothing anywhere can shorten it** — not coin, not an
/// item, not a building, not an action. A voyage is also never the only road:
/// the local quay is always open, so a wait is a choice you make for a better
/// price, never a gate you sit behind.
library;

import 'resources.dart';

/// Somewhere worth sending a hull.
class Destination {
  const Destination({
    required this.id,
    required this.name,
    required this.blurb,
    required this.days,
    required this.wants,
    required this.charterPerUnit,
    this.risk = 0.0,
  });

  final String id;
  final String name;
  final String blurb;

  /// Round trip, in game-days.
  final int days;

  /// What this market pays, relative to base price. Anything not listed pays
  /// [wrongCargoRate] — carrying the wrong cargo somewhere is poor trade, and
  /// it has to be clearly poor or every port feels the same.
  final Map<Resource, double> wants;

  /// Charter fee per unit of cargo.
  final double charterPerUnit;

  /// Chance per voyage of being taken. Doubles while privateers are working.
  final double risk;

  /// What a port pays for cargo it has no particular use for. Deliberately
  /// well under par: at 0.9 the destinations all felt interchangeable.
  static const double wrongCargoRate = 0.72;

  double payFor(Resource r) => wants[r] ?? wrongCargoRate;

  /// Coin per day per unit, which is the comparison that actually decides
  /// where a hull goes — a near port turning round three times beats a far
  /// one paying more but tying the hull up for a fortnight.
  double dailyRateFor(Resource r) =>
      (r.basePrice * payFor(r) - charterPerUnit) / days;
}

const List<Destination> kDestinations = [
  Destination(
    id: 'ostmark',
    name: 'Ostmark',
    blurb: 'A day down the coast, and a shipyard that never has enough '
        'timber, planks, rope or flax.',
    days: 3,
    charterPerUnit: 0.9,
    risk: 0.03,
    wants: {
      Resource.timber: 1.60,
      Resource.planks: 1.55,
      Resource.rope: 1.65,
      Resource.flax: 1.50,
    },
  ),
  Destination(
    id: 'greyhaven',
    name: 'Greyhaven',
    blurb: 'A garrison with more soldiers than farmland. It pays absurdly for '
        'food, and nothing beats it for tools and barrels.',
    days: 5,
    charterPerUnit: 1.3,
    risk: 0.07,
    // Food is cheap at home, so feeding a garrison needs a fat multiplier to
    // be worth a hull — and it gives an early port a second real option.
    wants: {
      Resource.grain: 2.80,
      Resource.fish: 2.80,
      Resource.barrels: 1.90,
      Resource.tools: 1.95,
    },
  ),
  Destination(
    id: 'the_reaches',
    name: 'The Reaches',
    blurb: 'Weeks of open water, and nobody out there asks what is in the '
        'hold. Spirits and powder fetch prices no lawful port will match.',
    days: 9,
    charterPerUnit: 2.1,
    risk: 0.14,
    // Has to pay roughly three times par, not twice: nine days is three
    // Ostmark round trips, so anything less and the long haul is never worth
    // a hull no matter how big the headline number looks.
    wants: {
      Resource.spirits: 4.20,
      Resource.powder: 4.20,
      Resource.sailcloth: 3.30,
      Resource.tools: 3.30,
      Resource.ore: 3.10,
    },
  ),
];

Destination destinationById(String id) =>
    kDestinations.firstWhere((d) => d.id == id);

/// A consignment at sea.
class Voyage {
  Voyage({
    required this.destinationId,
    required this.cargo,
    required this.departTick,
    required this.returnTick,
    required this.quotedCoin,
    this.escorted = false,
    this.riskFactor = 1.0,
  });

  final String destinationId;
  final Map<Resource, double> cargo;
  final int departTick;

  /// Written once at departure and never moved, in either direction.
  final int returnTick;

  /// What the factor promised. Quoted up front so sending a hull out is a
  /// decision with a known payoff, not a gamble on two axes at once.
  final int quotedCoin;

  final bool escorted;

  /// The captain's effect on danger, frozen at departure alongside the days and
  /// the quote.
  ///
  /// It used to be read live when the hull came home, while the captain's
  /// commission had already been taken out of [quotedCoin] at departure — so
  /// the payment and the benefit came from different moments. Sending with
  /// nobody retained and hiring a captain while the ships were out bought
  /// their protection for every hull already at sea without paying a penny of
  /// commission on any of them. A crossing now carries the terms it left under,
  /// which is the same rule the rest of the game follows.
  final double riskFactor;

  Destination get destination => destinationById(destinationId);

  double get totalCargo => cargo.values.fold(0.0, (s, v) => s + v);

  /// 0..1 along the crossing, for the sail creeping across the map.
  double progress(int tick) {
    final span = returnTick - departTick;
    if (span <= 0) return 1;
    return ((tick - departTick) / span).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'dest': destinationId,
        'cargo': cargo.map((k, v) =>
            MapEntry(k.name, double.parse(v.toStringAsFixed(3)))),
        'depart': departTick,
        'ret': returnTick,
        'quote': quotedCoin,
        'escort': escorted,
        'risk': riskFactor,
      };

  static Voyage? fromJson(Map<String, dynamic> j) {
    final id = j['dest'] as String;
    if (!kDestinations.any((d) => d.id == id)) return null;
    final cargo = <Resource, double>{};
    (j['cargo'] as Map<String, dynamic>).forEach((k, v) {
      try {
        cargo[Resource.byId(k)] = (v as num).toDouble();
      } on StateError {
        // Resource retired since the save was written.
      }
    });
    return Voyage(
      destinationId: id,
      cargo: cargo,
      departTick: (j['depart'] as num).toInt(),
      returnTick: (j['ret'] as num).toInt(),
      quotedCoin: (j['quote'] as num).toInt(),
      escorted: j['escort'] as bool? ?? false,
      // Saves written before the factor was frozen sail on their own terms.
      riskFactor: (j['risk'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// A voyage quote, itemised — who moved the number, and by how much.
///
/// Exists because the effect of a hire was invisible exactly where the player
/// makes the decision. The quay showed a price and the panel showed a total;
/// neither said "your factor got you eight percent of this, and took three and
/// a half back". A retinue you cannot see working is one you cannot judge.
class VoyageQuote {
  const VoyageQuote({
    required this.gross,
    required this.merchantBonus,
    required this.commission,
    required this.charterFee,
    required this.net,
  });

  /// What the cargo is worth at the destination before anyone is involved.
  final double gross;

  /// Added by the merchant's price bonus and any charter on sale prices.
  final double merchantBonus;

  /// Taken by the retinue as their cut. Always a cost.
  final double commission;

  /// The port's charge per unit landed. Nothing to do with the retinue.
  final double charterFee;

  /// What actually reaches the strongbox.
  final int net;

  bool get anyoneInvolved => merchantBonus.abs() >= 0.5 || commission >= 0.5;
}

/// The length of a crossing, itemised.
///
/// Measured in ticks rather than whole days, because rounding to days ate the
/// benefit outright in the one case that mattered most: a first captain on the
/// nearest lane. Three days at 0.85 is 2.55, which rounds straight back to
/// three — so she took her commission and delivered nothing, on the shortest
/// and most-used crossing in the game. A quarter of a day is eleven hours, and
/// the clock already runs in hours.
class VoyageDays {
  const VoyageDays({
    required this.base,
    required this.captainFactor,
    required this.charterFactor,
    required this.ticks,
    required this.ticksPerDay,
  });

  /// The lane's own length in days, with nobody retained.
  final int base;

  /// The captain's multiplier. Below 1 is faster.
  final double captainFactor;

  /// The charter's multiplier. Above 1 is a longer season.
  final double charterFactor;

  /// What the crossing actually takes, in game-hours.
  final int ticks;

  final int ticksPerDay;

  /// The crossing in days, fractional.
  double get days => ticks / ticksPerDay;

  bool get anyoneInvolved => captainFactor != 1.0 || charterFactor != 1.0;

  /// Days saved against the bare lane. Negative if a charter has lengthened it.
  double get saved => base - days;

  /// "3d", or "2.6d" when a crossing no longer lands on a whole day.
  String get label {
    final d = days;
    final whole = d.roundToDouble();
    return (d - whole).abs() < 0.05
        ? '${whole.round()}d'
        : '${d.toStringAsFixed(1)}d';
  }
}
