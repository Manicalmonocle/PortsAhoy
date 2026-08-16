/// People you pay to be better at things than you are.
///
/// Two tracks, hired in order and paid a wage every day they are on the books.
/// The ongoing wage is the point: a one-off purchase would just be a coin dump,
/// whereas a payroll is a standing decision you have to keep affording.
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
}

const List<Retainer> kRetinue = [
  // ---- Captains: speed and safety ---------------------------------------
  Retainer(
    track: RetinueTrack.captain,
    level: 1,
    name: 'Maren Holt',
    title: 'Sailing Master',
    blurb: 'Knows the inshore passages. Shaves a little off every crossing.',
    coinCost: 1200,
    dailyWage: 6,
    voyageSpeed: 0.85,
    voyageRisk: 0.80,
  ),
  Retainer(
    track: RetinueTrack.captain,
    level: 2,
    name: 'Iversen',
    title: 'Master Mariner',
    blurb: 'Carries her canvas longer than is strictly sensible.',
    coinCost: 3200,
    dailyWage: 14,
    voyageSpeed: 0.72,
    voyageRisk: 0.60,
  ),
  Retainer(
    track: RetinueTrack.captain,
    level: 3,
    name: 'Old Rennick',
    title: 'Commodore',
    blurb: 'Forty years at sea and has never lost a hull he was aboard.',
    coinCost: 7000,
    dailyWage: 28,
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
    coinCost: 1400,
    dailyWage: 7,
    sellBonus: 1.06,
    voyagePay: 1.08,
  ),
  Retainer(
    track: RetinueTrack.merchant,
    level: 2,
    name: 'Sowerby',
    title: 'Broker',
    blurb: 'Knows which captains are desperate and which are bluffing.',
    coinCost: 3600,
    dailyWage: 16,
    sellBonus: 1.12,
    voyagePay: 1.16,
  ),
  Retainer(
    track: RetinueTrack.merchant,
    level: 3,
    name: 'Halvard Meer',
    title: 'Merchant Prince',
    blurb: 'Sets the price on this coast, and everyone knows it.',
    coinCost: 7800,
    dailyWage: 30,
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
    coinCost: 1600,
    dailyWage: 8,
    autoCollect: AutoCollect.everyOtherDay,
    requiresBuildings: 8,
  ),
  Retainer(
    track: RetinueTrack.quartermaster,
    level: 2,
    name: 'Ansel Rook',
    title: 'Quartermaster',
    blurb: 'A cart round the whole port every single evening. You need never '
        'tap a shed again unless you want to.',
    coinCost: 4200,
    dailyWage: 18,
    autoCollect: AutoCollect.daily,
    requiresBuildings: 12,
  ),
  Retainer(
    track: RetinueTrack.quartermaster,
    level: 3,
    name: 'Mother Vell',
    title: 'Harbour Steward',
    blurb: 'Keeps carts moving hour by hour. Nothing sits in a yard longer '
        'than it takes to make.',
    coinCost: 9000,
    dailyWage: 34,
    autoCollect: AutoCollect.hourly,
    requiresBuildings: 16,
  ),
];

Retainer? retainerAt(RetinueTrack track, int level) {
  for (final r in kRetinue) {
    if (r.track == track && r.level == level) return r;
  }
  return null;
}
