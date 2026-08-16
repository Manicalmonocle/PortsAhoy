/// What the port has learned to build, and when.
///
/// The opening used to hand you three working sheds, ten hands and a catalogue
/// of seventeen buildings. That is not a tutorial, it is an inventory — there
/// was no moment where the game taught you one thing and then asked you to use
/// it. Buildings now arrive one at a time, each unlocked by something you did.
///
/// Pure data: a rule is a set of conditions, evaluated by `GameState` so this
/// file needs no import back into the tick loop. Unlocks are **sticky** — once
/// earned, a building stays available even if you sell the stock that earned
/// it, because taking something away again would only be confusing.
library;

import 'resources.dart';

class UnlockRule {
  const UnlockRule(
    this.id, {
    required this.text,
    this.minDay = 0,
    this.requires = const [],
    this.minStock = const {},
    this.minCoin = 0,
  });

  /// The building this unlocks.
  final String id;

  /// Shown on the locked card, so you always know what to go and do.
  final String text;

  final int minDay;

  /// Building ids that must already stand in the port.
  final List<String> requires;

  /// Stock you must be holding when the day turns over.
  final Map<Resource, double> minStock;

  final int minCoin;

  bool get isFromTheStart =>
      minDay == 0 && requires.isEmpty && minStock.isEmpty && minCoin == 0;
}

/// The tree, in the order it reveals itself.
const List<UnlockRule> kUnlockRules = [
  // ---- The first hour: hands in, goods out ------------------------------
  UnlockRule('forest_camp', text: 'Available from the start'),
  UnlockRule('fishing_wharf', text: 'Available from the start'),
  UnlockRule('house', text: 'Available from the start'),

  // ---- Feeding yourself --------------------------------------------------
  UnlockRule('farm', text: 'Reach day 3', minDay: 3),

  // ---- Your first refining chain ----------------------------------------
  UnlockRule('sawmill',
      text: 'Hold 40 timber', minStock: {Resource.timber: 40}),
  UnlockRule('warehouse', text: 'Build a sawmill', requires: ['sawmill']),
  UnlockRule('flax_field', text: 'Build a sawmill', requires: ['sawmill']),

  // ---- The flax question -------------------------------------------------
  UnlockRule('ropewalk', text: 'Build a flax field', requires: ['flax_field']),
  UnlockRule('weaver', text: 'Build a ropewalk', requires: ['ropewalk']),
  UnlockRule('cooperage', text: 'Build a warehouse', requires: ['warehouse']),

  // ---- Metal -------------------------------------------------------------
  UnlockRule('mine', text: 'Reach day 12', minDay: 12),
  UnlockRule('smithy', text: 'Build an iron mine', requires: ['mine']),

  // ---- Spending coin -----------------------------------------------------
  UnlockRule('import_berth', text: 'Hold 1,200 coin', minCoin: 1200),

  // ---- The dark trade, entirely optional ---------------------------------
  //
  // These used to be a chain: each dark shed unlocked only once you had BUILT
  // the previous one. Measured against a complete human run — 93 days, won —
  // that meant the Distillery appeared on day 25, the Powder Mill on day 51,
  // and the Bonded Cellar and Privateer Berth NEVER APPEARED AT ALL, because
  // the player never built the shed each one was hiding behind. The whole late
  // half of the subsystem was unreachable in a winning run, which is why it
  // read as "too late to matter": it wasn't late, it was absent.
  //
  // Two links cut, no payoff number touched:
  //
  //   The Bonded Cellar hangs off the warehouse, not the distillery. Hiding
  //   contraband used to be gated behind producing it, so a first dark run had
  //   to get exposed before it could buy concealment — backwards, and the
  //   reason the dark trade punished the exact curiosity it wanted to reward.
  //
  //   The Privateer Berth hangs off the smithy, not the powder mill. It is the
  //   building this game is named after and it sat four deep behind a chain
  //   that only starts once iron is running. Its cost — 40 rope and 30
  //   sailcloth — already means a ropewalk and a weaver, so the resources gate
  //   it honestly without the unlock doing it a second time.
  UnlockRule('distillery', text: 'Reach day 25', minDay: 25),
  UnlockRule('bonded_cellar',
      text: 'Build a warehouse', requires: ['warehouse']),
  UnlockRule('powder_mill', text: 'Build a smithy', requires: ['smithy']),
  UnlockRule('privateer_berth', text: 'Build a smithy', requires: ['smithy']),
];

UnlockRule? unlockRuleFor(String buildingId) {
  for (final r in kUnlockRules) {
    if (r.id == buildingId) return r;
  }
  return null;
}

/// Ids available the moment a new game starts.
Set<String> get kInitiallyUnlocked =>
    kUnlockRules.where((r) => r.isFromTheStart).map((r) => r.id).toSet();
