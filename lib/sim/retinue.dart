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

enum RetinueTrack { captain, merchant, quartermaster }

/// How much of the carting a quartermaster takes off your hands.
///
/// This exists because a port of twenty-five sheds turns collecting from a
/// satisfying beat into a chore. It is earned with coin and a standing wage —
/// never sold — and it arrives late, once the tedium is real.
/// Every tier below [none] also empties any yard that fills, so a shed can
/// never stall unwatched. That guarantee is free at all levels — it was a
/// mistake to sell it as the first tier, because a yard filling is rare once
/// warehouses have widened them, so the hire appeared to do nothing at all.
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

  // ---- Quartermasters: the carting ---------------------------------------
  Retainer(
    track: RetinueTrack.quartermaster,
    level: 1,
    name: 'Tam Fowler',
    title: 'Yard Clerk',
    blurb: 'Runs a cart round the port every other evening, and empties any '
        'yard that fills in between.',
    coinCost: 600,
    dailyWage: 6,
    autoCollect: AutoCollect.everyOtherDay,
    requiresBuildings: 5,
  ),
  Retainer(
    track: RetinueTrack.quartermaster,
    level: 2,
    name: 'Ansel Rook',
    title: 'Quartermaster',
    blurb: 'A cart round the whole port every single evening. You need never '
        'tap a shed again unless you want to.',
    coinCost: 2800,
    dailyWage: 15,
    autoCollect: AutoCollect.daily,
    requiresBuildings: 9,
  ),
  Retainer(
    track: RetinueTrack.quartermaster,
    level: 3,
    name: 'Mother Vell',
    title: 'Harbour Steward',
    blurb: 'Keeps carts moving hour by hour. Nothing sits in a yard longer '
        'than it takes to make.',
    coinCost: 6600,
    dailyWage: 30,
    autoCollect: AutoCollect.hourly,
    requiresBuildings: 13,
  ),
];

Retainer? retainerAt(RetinueTrack track, int level) {
  for (final r in kRetinue) {
    if (r.track == track && r.level == level) return r;
  }
  return null;
}
