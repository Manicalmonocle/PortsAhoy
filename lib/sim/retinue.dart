/// People you pay to be better at things than you are.
///
/// Three tracks, hired in order and paid a wage every day they are on the
/// books.
/// The ongoing wage is the point: a one-off purchase would just be a coin dump,
/// whereas a payroll is a standing decision you have to keep affording.
///
/// ON PRICING. The first rung of each track is deliberately cheap — under a
/// fifteenth of the lighthouse's coin cost. An upgrade you cannot afford until
/// the game is already decided shapes nothing; these are meant to be an early
/// decision you build a run around, not a late-game footnote.
///
/// ON COMMISSION, AND WHY THE FLAT WAGE HAD TO GO. The merchant used to cost a
/// flat 5c a day and return a percentage of everything you sold. Measured on a
/// mid-game consignment that was +150c a crossing against 5c a day — a tenfold
/// return that paid its hire back in four voyages and printed money after. The
/// fault was structural, not numerical: **a flat cost against a percentage
/// benefit is always eventually free**, because the benefit grows with your
/// cargo all run while the cost does not. No amount of tuning the 5c fixes
/// that; it only moves the day it stops mattering.
///
/// So the earners are paid the way factors and shipmasters actually were — a
/// small retainer plus [commission] on what passes through their hands. The
/// cost now scales with the benefit, and the hire stays a judgement about how
/// much you intend to trade rather than a box to tick on the way past.
///
/// The captain is the interesting one: commission is a *pure* cost to them,
/// since they sell you speed and safety rather than price. Retaining one means
/// every crossing is quicker and likelier to arrive, and pays a little less.
/// The quartermaster stays on a flat wage — carting earns nothing to take a
/// cut of, and convenience should not be taxed per voyage.
///
/// ON CAPTAINS AND TIME. A better captain sails faster, which shortens the
/// voyages you send **from now on**. It never moves a hull already at sea —
/// that duration is fixed the moment she clears the harbour and nothing can
/// touch it. You can buy a better fleet; you cannot buy back a crossing you
/// have already committed to.
library;

enum RetinueTrack { captain, merchant, privateer, reeve }

/// How much of the carting the harbour does for you, without being asked.
///
/// This used to be a paid officer — the quartermaster — but a player was right
/// that carting is convenience, not strategy: it should never compete for coin
/// or an officer's berth against the captain and the merchant, who change how
/// the economy works. So it is no longer hired. It escalates on its own as the
/// port grows past the point where hand-collecting turns from a satisfying
/// beat into a chore, which is exactly when the old quartermaster's building
/// gates opened anyway ([autoCollectFor]).
///
/// Every tier below [none] also empties any yard that fills, so a shed can
/// never stall unwatched.
enum AutoCollect {
  /// Nobody. You cart every yard in yourself.
  none,

  /// Carts the whole port in every second evening.
  everyOtherDay,

  /// Carts the whole port in every evening.
  daily,

  /// Carts everything in, every hour.
  hourly,
}

/// The carting the port does for itself at a given size.
///
/// The thresholds are the quartermaster's old building gates (5, 9, 13), kept
/// exactly so the pacing of when the tedium lifts is unchanged — only the
/// price is gone.
AutoCollect autoCollectFor(int producingSheds) {
  if (producingSheds >= 13) return AutoCollect.hourly;
  if (producingSheds >= 9) return AutoCollect.daily;
  if (producingSheds >= 5) return AutoCollect.everyOtherDay;
  return AutoCollect.none;
}

class Retainer {
  const Retainer({
    required this.track,
    required this.level,
    required this.name,
    required this.title,
    required this.blurb,
    required this.coinCost,
    required this.dailyWage,
    this.voyageSpeed = 1.0,
    this.voyageRisk = 1.0,
    this.sellBonus = 1.0,
    this.voyagePay = 1.0,
    this.autoCollect = AutoCollect.none,
    this.requiresBuildings = 0,
    this.commission = 0.0,
    this.prizeBonus = 0.0,
    this.ripenSpeed = 1.0,
    this.bootyBonus = 1.0,
    this.requiresBuilding,
  });

  final RetinueTrack track;

  /// 1, 2 or 3. You must hire the level below before the one above.
  final int level;

  final String name;
  final String title;
  final String blurb;

  final int coinCost;
  final int dailyWage;

  /// Multiplier on the days a *new* voyage takes.
  final double voyageSpeed;

  /// Multiplier on the chance a voyage is taken.
  final double voyageRisk;

  /// Multiplier on what you are paid at your own quay.
  final double sellBonus;

  /// Multiplier on what a factor abroad pays.
  final double voyagePay;

  /// How much carting this person does for you.
  final AutoCollect autoCollect;

  /// Producing sheds you must have before this hire is on offer. Keeps the
  /// quartermaster out of the early game, where collecting is the point.
  final int requiresBuildings;

  /// The cut this person takes of every sale they have a hand in — at the quay
  /// and on the factor's account abroad. Taken off the top, before the coin
  /// reaches you.
  final double commission;

  /// Added to the chance a boarding succeeds. A privateer captain's whole
  /// trade: better odds at the rail.
  final double prizeBonus;

  /// How much faster this officer brings a ripening shed on.
  ///
  /// The reeve's whole effect, and deliberately something nothing else in the
  /// game touches. A captain buys speed at sea and a merchant buys price; an
  /// honest port running herds had neither of those to spend an officer's
  /// berth on, and nobody to spend it with — reported from play as "on a good
  /// run there's just merchant and captain to buy".
  ///
  /// Time is the husbandry route's whole currency, so an officer who buys time
  /// is the one worth having. It also means a reeve hired early is worth far
  /// more than one hired late, which is the same bet the sheds themselves are.
  final double ripenSpeed;

  /// Multiplier on the tonnage a won prize lands — the booty. Above 1 means a
  /// fuller hold, spice included.
  final double bootyBonus;

  /// A building that must already stand before this hire is offered at all.
  /// Keeps the privateer captain off the books of a port that has never built
  /// a privateer berth and has no use for them.
  final String? requiresBuilding;
}

/// How many tracks you may have someone on at once.
///
/// A small port cannot keep three salaried officers on the books, and the game
/// is more interesting when it cannot: the first hire has to be a choice
/// between price, speed and having your yards carted for you, rather than the
/// first item on a shopping list you will finish anyway. The cap widens as the
/// port does, so a large harbour eventually keeps all three — earned, not
/// assumed.
int officerCapacityFor(int producingSheds) {
  if (producingSheds >= 16) return 3;
  if (producingSheds >= 9) return 2;
  return 1;
}

const List<Retainer> kRetinue = [
  // ---- Captains: speed and safety ---------------------------------------
  Retainer(
    track: RetinueTrack.captain,
    level: 1,
    name: 'Maren Holt',
    title: 'Sailing Master',
    blurb: 'Knows the inshore passages. Shaves a little off every crossing.',
    coinCost: 450,
    dailyWage: 2,
    commission: 0.03,
    voyageSpeed: 0.85,
    voyageRisk: 0.80,
  ),
  Retainer(
    track: RetinueTrack.captain,
    level: 2,
    name: 'Iversen',
    title: 'Master Mariner',
    blurb: 'Carries her canvas longer than is strictly sensible.',
    coinCost: 2200,
    dailyWage: 4,
    commission: 0.055,
    voyageSpeed: 0.72,
    voyageRisk: 0.60,
  ),
  Retainer(
    track: RetinueTrack.captain,
    level: 3,
    name: 'Old Rennick',
    title: 'Commodore',
    blurb: 'Forty years at sea and has never lost a hull he was aboard.',
    coinCost: 5200,
    dailyWage: 7,
    commission: 0.08,
    voyageSpeed: 0.60,
    voyageRisk: 0.45,
  ),

  // ---- Merchants: prices --------------------------------------------------
  Retainer(
    track: RetinueTrack.merchant,
    level: 1,
    name: 'Bettine Cray',
    title: 'Factor',
    blurb: 'Haggles so you do not have to. A few percent on everything.',
    coinCost: 500,
    dailyWage: 2,
    commission: 0.035,
    sellBonus: 1.06,
    voyagePay: 1.08,
  ),
  Retainer(
    track: RetinueTrack.merchant,
    level: 2,
    name: 'Sowerby',
    title: 'Broker',
    blurb: 'Knows which captains are desperate and which are bluffing.',
    coinCost: 2400,
    dailyWage: 4,
    commission: 0.07,
    sellBonus: 1.12,
    voyagePay: 1.16,
  ),
  Retainer(
    track: RetinueTrack.merchant,
    level: 3,
    name: 'Halvard Meer',
    title: 'Merchant Prince',
    blurb: 'Sets the price on this coast, and everyone knows it.',
    coinCost: 5600,
    dailyWage: 7,
    commission: 0.11,
    sellBonus: 1.20,
    voyagePay: 1.26,
  ),

  // ---- Privateer captains: the odds and the booty ------------------------
  //
  // The dark trade's own officer, and only offered once a privateer berth
  // stands ([requiresBuilding]). A captain sells honest speed and safety; a
  // privateer captain sells a better chance at the rail and a fuller hold when
  // the boarding goes your way. On a hard run, where spice is what carries you
  // and the honest chains are throttled, this is the hire you take the third
  // berth for — instead of the merchant, whose prices you have less to sell to.
  Retainer(
    track: RetinueTrack.privateer,
    level: 1,
    name: 'Sable Quill',
    title: 'Boarding Master',
    blurb: 'Has taken more decks than she can rightly remember. Better odds '
        'at the rail, and a fuller hold when it goes your way.',
    coinCost: 500,
    dailyWage: 3,
    prizeBonus: 0.08,
    bootyBonus: 1.15,
    requiresBuilding: 'privateer_berth',
  ),
  Retainer(
    track: RetinueTrack.privateer,
    level: 2,
    name: 'Redd Coombe',
    title: 'Sea Wolf',
    blurb: 'The revenue know his sail on the horizon and put about for home.',
    coinCost: 2400,
    dailyWage: 6,
    prizeBonus: 0.15,
    bootyBonus: 1.32,
    requiresBuilding: 'privateer_berth',
  ),
  Retainer(
    track: RetinueTrack.privateer,
    level: 3,
    name: 'Captain Mordaunt',
    title: 'Pirate Captain',
    blurb: 'Flies no flag but his own. What his boarders leave behind was not '
        'worth the carrying.',
    coinCost: 5600,
    dailyWage: 10,
    prizeBonus: 0.22,
    bootyBonus: 1.55,
    requiresBuilding: 'privateer_berth',
  ),

  // ---- Reeves: time ------------------------------------------------------
  //
  // Behind a grange, because an officer for the herds with no herds to keep is
  // a wage for nothing. The honest counterpart to the privateer captain: that
  // track only appears once a berth stands, and this one only once a grange
  // does, so a port sees the officers its own choices earned.
  Retainer(
    track: RetinueTrack.reeve,
    level: 1,
    name: 'Alderman Fitch',
    title: 'Reeve',
    blurb: 'Knows which field to rest and which ewe to keep. Everything that '
        'ripens, ripens sooner.',
    coinCost: 600,
    dailyWage: 2,
    ripenSpeed: 1.25,
    requiresBuilding: 'grange',
  ),
  Retainer(
    track: RetinueTrack.reeve,
    level: 2,
    name: 'Mother Aubrey',
    title: 'Stockmaster',
    blurb: 'Has not lost a lamb in eleven winters, and says so often.',
    coinCost: 2600,
    dailyWage: 4,
    ripenSpeed: 1.5,
    requiresBuilding: 'grange',
  ),
  Retainer(
    track: RetinueTrack.reeve,
    level: 3,
    name: 'Havel Brandt',
    title: 'Steward of the Fold',
    blurb: 'Runs the land as an instrument. The herds come on as though the '
        'season were longer here.',
    coinCost: 5400,
    dailyWage: 7,
    ripenSpeed: 1.8,
    requiresBuilding: 'grange',
  ),
];

Retainer? retainerAt(RetinueTrack track, int level) {
  for (final r in kRetinue) {
    if (r.track == track && r.level == level) return r;
  }
  return null;
}
