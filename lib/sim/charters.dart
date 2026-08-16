/// What you carry from one run into the next.
///
/// Finishing the lighthouse used to be a dead end: the dialog fired and you
/// were handed back a port with nothing left to do. A completed run now earns
/// a **charter** — a standing condition you can apply to the next voyage.
///
/// THE RULE THAT KEEPS THIS HONEST. Every charter has a weight. Hardships have
/// a positive weight and *pay* you budget; advantages have a negative weight
/// and *spend* it. You begin with only [kBaseBudget], so a run of pure
/// advantages is arithmetically impossible — the only way to make something
/// easier is to first make something else harder. The game therefore gets more
/// interesting across runs rather than steadily softer, which is the failure
/// mode of every unlock ladder that only ever adds.
///
/// Charters are earned by playing and are never for sale.
library;

/// Advantage you may take before earning any hardship at all.
const int kBaseBudget = 2;

class Charter {
  const Charter({
    required this.id,
    required this.name,
    required this.blurb,
    required this.weight,
    this.hazardGap = 1.0,
    this.hazardSeverity = 1.0,
    this.salePrice = 1.0,
    this.production = 1.0,
    this.foodUse = 1.0,
    this.growth = 1.0,
    this.storage = 1.0,
    this.voyageDays = 1.0,
    this.lighthouseCost = 1.0,
    this.startCoin = 0,
    this.startPopulation = 0,
  });

  final String id;
  final String name;
  final String blurb;

  /// Positive earns budget (a hardship); negative spends it (an advantage).
  final int weight;

  bool get isHardship => weight > 0;

  /// Multiplier on the quiet days between events. Below 1 means more weather.
  final double hazardGap;

  /// Multiplier on how hard a hazard bites.
  final double hazardSeverity;

  /// Multiplier on coin from selling, at the quay and abroad.
  final double salePrice;

  /// Multiplier on everything the sheds make.
  final double production;

  /// Multiplier on what the town eats.
  final double foodUse;

  /// Multiplier on the chance someone moves in.
  final double growth;

  /// Multiplier on every store's capacity.
  final double storage;

  /// Multiplier on how long a crossing takes.
  final double voyageDays;

  /// Multiplier on everything the lighthouse costs.
  final double lighthouseCost;

  final int startCoin;
  final int startPopulation;
}

const List<Charter> kCharters = [
  // ---- Hardships: these pay for the advantages ---------------------------
  Charter(
    id: 'hard_weather',
    name: 'Hard Weather',
    blurb: 'The glass is never steady. Storms come round twice as often.',
    weight: 2,
    hazardGap: 0.5,
  ),
  Charter(
    id: 'bitter_seas',
    name: 'Bitter Seas',
    blurb: 'When the weather turns it turns hard. Every hazard bites deeper.',
    weight: 2,
    hazardSeverity: 1.6,
  ),
  Charter(
    id: 'thin_purses',
    name: 'Thin Purses',
    blurb: 'The coast is poor this decade. Everything you sell fetches less.',
    weight: 2,
    salePrice: 0.80,
  ),
  Charter(
    id: 'a_grander_light',
    name: 'A Grander Light',
    blurb: 'The Admiralty wants a tower worth the name. Half again as much '
        'of everything.',
    weight: 3,
    lighthouseCost: 1.5,
  ),
  Charter(
    id: 'poor_soil',
    name: 'Poor Soil',
    blurb: 'Thin ground and short summers. Every shed yields less.',
    weight: 1,
    production: 0.85,
  ),
  Charter(
    id: 'hungry_town',
    name: 'A Hungry Town',
    blurb: 'Cold quarters and hard work. Your people eat far more.',
    weight: 1,
    foodUse: 1.4,
  ),
  Charter(
    id: 'cramped_stores',
    name: 'Cramped Stores',
    blurb: 'Damp cellars and low roofs. Every store holds less.',
    weight: 1,
    storage: 0.7,
  ),
  Charter(
    id: 'distant_waters',
    name: 'Distant Waters',
    blurb: 'The lanes are long this season. Every crossing takes half again '
        'as long.',
    weight: 1,
    voyageDays: 1.5,
  ),
  Charter(
    id: 'a_quiet_quay',
    name: 'A Quiet Quay',
    blurb: 'Word has not got round. Nobody much wants to settle here.',
    weight: 1,
    growth: 0.5,
  ),

  // ---- Advantages: these cost budget --------------------------------------
  Charter(
    id: 'rich_contracts',
    name: 'Rich Contracts',
    blurb: 'A good name on the coast. Everything you sell fetches more.',
    weight: -2,
    salePrice: 1.25,
  ),
  Charter(
    id: 'fair_winds',
    name: 'A Fair Season',
    blurb: 'Long light and steady weather. Every shed runs sweetly.',
    weight: -2,
    production: 1.15,
  ),
  Charter(
    id: 'settled_coast',
    name: 'A Settled Coast',
    blurb: 'Quiet water and quiet years. The weather leaves you be.',
    weight: -2,
    hazardGap: 1.6,
  ),
  Charter(
    id: 'deep_cellars',
    name: 'Deep Cellars',
    blurb: 'Dry stone and good roofs. Every store holds half again as much.',
    weight: -1,
    storage: 1.5,
  ),
  Charter(
    id: 'full_nets',
    name: 'Full Nets',
    blurb: 'The banks are thick with herring. Your people eat less of your '
        'stores.',
    weight: -1,
    foodUse: 0.7,
  ),
  Charter(
    id: 'willing_hands',
    name: 'Willing Hands',
    blurb: 'Three families came with you, and word travels fast.',
    weight: -1,
    startPopulation: 3,
    growth: 1.4,
  ),
  Charter(
    id: 'a_full_purse',
    name: 'A Full Purse',
    blurb: 'You did not take this post empty-handed.',
    weight: -1,
    startCoin: 700,
  ),
  Charter(
    id: 'swift_hulls',
    name: 'Swift Hulls',
    blurb: 'Clean bottoms and willing crews. Crossings are quicker.',
    weight: -1,
    voyageDays: 0.7,
  ),
];

Charter? charterById(String id) {
  for (final c in kCharters) {
    if (c.id == id) return c;
  }
  return null;
}

/// The charters in force for a run, folded into one set of numbers.
class CharterSet {
  CharterSet(this.active);

  final List<Charter> active;

  static CharterSet get none => CharterSet(const []);

  double _product(double Function(Charter) f) =>
      active.fold(1.0, (a, c) => a * f(c));

  double get hazardGap => _product((c) => c.hazardGap);
  double get hazardSeverity => _product((c) => c.hazardSeverity);
  double get salePrice => _product((c) => c.salePrice);
  double get production => _product((c) => c.production);
  double get foodUse => _product((c) => c.foodUse);
  double get growth => _product((c) => c.growth);
  double get storage => _product((c) => c.storage);
  double get voyageDays => _product((c) => c.voyageDays);
  double get lighthouseCost => _product((c) => c.lighthouseCost);

  int get startCoin => active.fold(0, (a, c) => a + c.startCoin);
  int get startPopulation => active.fold(0, (a, c) => a + c.startPopulation);

  /// Total hardship taken — the difficulty a completed run is recorded under.
  int get difficulty =>
      active.where((c) => c.isHardship).fold(0, (a, c) => a + c.weight);

  int get budgetEarned => difficulty;
  int get budgetSpent =>
      active.where((c) => !c.isHardship).fold(0, (a, c) => a - c.weight);

  /// A selection is legal when the advantages taken are paid for.
  bool get isLegal => budgetSpent <= budgetEarned + kBaseBudget;

  int get budgetLeft => budgetEarned + kBaseBudget - budgetSpent;

  List<String> get ids => active.map((c) => c.id).toList();

  static CharterSet fromIds(Iterable<String> ids) =>
      CharterSet(ids.map(charterById).whereType<Charter>().toList());
}
