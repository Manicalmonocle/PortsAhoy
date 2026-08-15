import 'resources.dart';

/// Game-hours of output a shed's yard holds before it idles.
///
/// A week, not the four days it started at: at 2x speed four days is under a
/// minute, which turned collecting from a satisfying beat into a chore with a
/// stopwatch. Warehouses raise it further — see [Building.yardBonus].
const double kHoldTicks = 168;

/// What a building does each tick, per assigned worker.
///
/// A building with `inputs` empty is an extractor (forest camp, farm); one with
/// inputs is a workshop that refines. Rates are per worker per tick, and one
/// tick is one game-hour (24 ticks to the day).
class BuildingDef {
  const BuildingDef({
    required this.id,
    required this.name,
    required this.icon,
    required this.blurb,
    required this.maxWorkers,
    required this.cost,
    this.coinCost = 0,
    this.inputs = const {},
    this.outputs = const {},
    this.housing = 0,
    this.storage = 0,
    this.concealPerWorker = 0,
    this.upkeep = const {},
    this.imports = false,
    this.workSite = false,
    this.buildable = true,
    this.footprint = 2,
  });

  final String id;
  final String name;
  final String icon;
  final String blurb;

  final int maxWorkers;

  /// Resource cost to construct, alongside [coinCost].
  final Map<Resource, double> cost;
  final int coinCost;

  /// Consumed per worker per tick.
  final Map<Resource, double> inputs;

  /// Produced per worker per tick.
  final Map<Resource, double> outputs;

  /// Population capacity added (houses).
  final int housing;

  /// Storage capacity added to every resource (warehouses).
  final double storage;

  /// Contraband hidden from a revenue inspection, per assigned worker.
  ///
  /// Priced in hands rather than coin on purpose: concealment you could buy
  /// would let the very coin surplus this layer exists to drain switch the
  /// enforcement system off permanently. Priced in workers it self-caps,
  /// because population is bounded by housing.
  final double concealPerWorker;

  /// Consumed per worker per tick just to keep the crew standing by.
  ///
  /// Deliberately NOT folded into [inputs]: `isWorkshop` keys off inputs, and a
  /// berth counted as a workshop would report a negative margin and break the
  /// refining-beats-raw balance invariants.
  final Map<Resource, double> upkeep;

  /// Spends coin per worker-tick to land raw cargo. See `_landImports`.
  final bool imports;

  /// Takes a crew but produces nothing — an event-inserted work site.
  final bool workSite;

  /// False hides it from the Build tab (event-inserted structures).
  final bool buildable;

  /// Side length of the square this building occupies, in tiles.
  final int footprint;

  /// True when this building draws hands and does something with them.
  ///
  /// Extractors and workshops have outputs; the import berth spends coin
  /// instead; a work site has neither but still takes a crew. All three need a
  /// worker stepper in the Port tab, and all three are what the balance probe
  /// means by "somewhere to put a hand".
  bool get isProducer => outputs.isNotEmpty || imports || workSite;
  bool get isWorkshop => inputs.isNotEmpty;
  bool get isCrewed => upkeep.isNotEmpty;

  /// Anything the player can post hands to, and therefore anything that needs
  /// a worker stepper in the Port tab.
  ///
  /// Wider than [isProducer]: a bonded cellar and a privateer berth both take a
  /// crew without producing a thing. Routing the UI on [isProducer] would file
  /// them as infrastructure and leave them permanently unstaffable.
  bool get isStaffable => maxWorkers > 0;

  /// Coin value added per worker-tick at neutral prices. Used by the UI to
  /// show players which chains are worth staffing, and by tests to assert the
  /// refining tiers stay more profitable than dumping raws.
  double get marginPerWorkerTick {
    double v = 0;
    outputs.forEach((r, q) => v += r.basePrice * q);
    inputs.forEach((r, q) => v -= r.basePrice * q);
    return v;
  }

  /// Coin of output value wrung from each unit of [r] consumed.
  ///
  /// The second axis of the core decision: when flax is scarce the ropewalk
  /// wins on this, when hands are scarce the weaver wins on
  /// [marginPerWorkerTick]. Neither dominates, so which shed you staff depends
  /// on which resource is actually your bottleneck that hour.
  double outputValuePerUnitOf(Resource r) {
    final need = inputs[r] ?? 0;
    if (need <= 0) return double.infinity;
    double v = 0;
    outputs.forEach((o, q) => v += o.basePrice * q);
    return v / need;
  }
}

/// The full building catalogue. Data-driven: adding a chain is a list entry.
const List<BuildingDef> kBuildingDefs = [
  // ---- Extractors -------------------------------------------------------
  BuildingDef(
    id: 'forest_camp',
    name: 'Forest Camp',
    icon: '🌲',
    blurb: 'Fells the island pines. The bottom of nearly every chain.',
    maxWorkers: 4,
    coinCost: 60,
    cost: {},
    outputs: {Resource.timber: 0.30},
  ),
  BuildingDef(
    id: 'fishing_wharf',
    name: 'Fishing Wharf',
    icon: '🎣',
    blurb: 'Feeds the town without touching farmland.',
    maxWorkers: 4,
    coinCost: 60,
    cost: {},
    outputs: {Resource.fish: 0.25},
  ),
  BuildingDef(
    id: 'farm',
    name: 'Farm',
    icon: '🚜',
    blurb: 'Steadier than fishing, and grain keeps.',
    maxWorkers: 4,
    coinCost: 80,
    cost: {},
    outputs: {Resource.grain: 0.28},
  ),
  BuildingDef(
    id: 'flax_field',
    name: 'Flax Field',
    icon: '🌱',
    blurb: 'Feeds both the ropewalk and the weaver. You will not have enough.',
    maxWorkers: 4,
    coinCost: 90,
    cost: {},
    outputs: {Resource.flax: 0.20},
  ),
  BuildingDef(
    id: 'mine',
    name: 'Iron Mine',
    icon: '⛏️',
    blurb: 'Slow, expensive, and the only road to tools.',
    maxWorkers: 4,
    coinCost: 220,
    cost: {Resource.planks: 30},
    outputs: {Resource.ore: 0.15},
  ),

  // ---- Workshops --------------------------------------------------------
  BuildingDef(
    id: 'sawmill',
    name: 'Sawmill',
    icon: '🪚',
    blurb: 'Timber into planks. One forester feeds exactly one sawyer.',
    maxWorkers: 3,
    coinCost: 150,
    cost: {Resource.timber: 20},
    inputs: {Resource.timber: 0.30},
    outputs: {Resource.planks: 0.25},
  ),
  BuildingDef(
    id: 'ropewalk',
    name: 'Ropewalk',
    icon: '🪢',
    blurb: 'Wrings the most coin out of every stalk of flax — but ties up hands.',
    maxWorkers: 3,
    coinCost: 200,
    cost: {Resource.planks: 25},
    inputs: {Resource.flax: 0.25},
    outputs: {Resource.rope: 0.20},
  ),
  BuildingDef(
    id: 'cooperage',
    name: 'Cooperage',
    icon: '🛢️',
    blurb: 'Barrels sell well and only cost planks.',
    maxWorkers: 3,
    coinCost: 240,
    cost: {Resource.planks: 30},
    inputs: {Resource.planks: 0.25},
    outputs: {Resource.barrels: 0.17},
  ),
  BuildingDef(
    id: 'weaver',
    name: 'Weaver',
    icon: '⛵',
    blurb: 'Pays far more per worker than the ropewalk — and eats twice the flax.',
    maxWorkers: 3,
    coinCost: 280,
    cost: {Resource.planks: 30},
    inputs: {Resource.flax: 0.45},
    outputs: {Resource.sailcloth: 0.18},
  ),
  BuildingDef(
    id: 'smithy',
    name: 'Smithy',
    icon: '🔨',
    blurb: 'The deepest chain in the port, and the richest.',
    maxWorkers: 3,
    coinCost: 400,
    cost: {Resource.planks: 40},
    inputs: {Resource.ore: 0.25, Resource.planks: 0.10},
    outputs: {Resource.tools: 0.12},
  ),

  // ---- The coin sink ----------------------------------------------------
  BuildingDef(
    id: 'import_berth',
    name: 'Import Berth',
    icon: '⚓',
    blurb: 'Standing orders with foreign factors. Spends coin by the hour to '
        'land raw cargo — never a finished good.',
    maxWorkers: 3,
    coinCost: 320,
    cost: {Resource.planks: 35},
    imports: true,
  ),

  // ---- The dark trade ---------------------------------------------------
  // Building any one of these opens the free-trader market. A port that never
  // builds one never sees contraband, is never inspected, and can still win.
  BuildingDef(
    id: 'distillery',
    name: 'Distillery',
    icon: '🥃',
    blurb: 'Grain and barrels into spirits. Argues with the supper table '
        'every single hour.',
    maxWorkers: 3,
    coinCost: 300,
    cost: {Resource.planks: 35, Resource.barrels: 10},
    inputs: {Resource.grain: 0.30, Resource.barrels: 0.05},
    outputs: {Resource.spirits: 0.10},
  ),
  BuildingDef(
    id: 'powder_mill',
    name: 'Powder Mill',
    icon: '💥',
    blurb: 'Ore and timber into powder. Sells dear, and arms the mole '
        'against raiders.',
    maxWorkers: 2,
    coinCost: 460,
    cost: {Resource.planks: 45, Resource.tools: 12},
    inputs: {Resource.ore: 0.20, Resource.timber: 0.30},
    outputs: {Resource.powder: 0.055},
  ),
  BuildingDef(
    id: 'bonded_cellar',
    name: 'Bonded Cellar',
    icon: '🚪',
    blurb: 'Hides 45 units of contraband per hand posted to it. An empty '
        'cellar hides nothing.',
    maxWorkers: 2,
    coinCost: 340,
    cost: {Resource.planks: 40, Resource.timber: 30},
    concealPerWorker: 45,
  ),
  BuildingDef(
    id: 'privateer_berth',
    name: 'Privateer Berth',
    icon: '🏴',
    blurb: 'A crew on standby, eating stores. Takes prizes off the quay and '
        'beats raiders off the mole.',
    maxWorkers: 4,
    coinCost: 700,
    cost: {Resource.planks: 60, Resource.rope: 40, Resource.sailcloth: 30},
    upkeep: {
      Resource.barrels: 0.030,
      Resource.rope: 0.035,
      Resource.sailcloth: 0.025,
    },
  ),

  // ---- Infrastructure ---------------------------------------------------
  BuildingDef(
    id: 'house',
    name: 'Cottage Row',
    icon: '🏠',
    blurb: 'Houses five. The town also wants a couple of days of food put by '
        'before anyone new moves in.',
    maxWorkers: 0,
    coinCost: 100,
    cost: {Resource.planks: 15},
    housing: 5,
  ),
  BuildingDef(
    id: 'warehouse',
    name: 'Warehouse',
    icon: '📦',
    blurb: '+150 storage for every good. Your only real limit while away.',
    maxWorkers: 0,
    coinCost: 180,
    cost: {Resource.planks: 25},
    storage: 150,
  ),
];

BuildingDef defById(String id) => kBuildingDefs.firstWhere((d) => d.id == id);

/// Building any of these opens the dark trade: free traders start calling, and
/// contraband becomes reachable. A port with none of them never sees a revenue
/// cutter, because there is nothing for one to find.
const Set<String> kDarkBuildingIds = {
  'distillery',
  'powder_mill',
  'bonded_cellar',
  'privateer_berth',
};

/// A constructed building with workers assigned to it.
class Building {
  Building({
    required this.defId,
    this.workers = 0,
    Resource? importResource,
    this.col = -1,
    this.row = -1,
  }) : importResource = importResource ?? kImportables.first;

  final String defId;
  int workers;

  /// Top-left tile of this building's footprint, or -1 when it has not been
  /// placed yet (a fresh build, or a save written before the map existed).
  int col;
  int row;

  bool get isPlaced => col >= 0 && row >= 0;

  /// Which raw cargo an import berth has standing orders for.
  Resource importResource;

  BuildingDef get def => defById(defId);

  /// Fraction of the last tick the building actually ran at. 1.0 means fully
  /// supplied; lower means it was starved of an input (or, for an import
  /// berth, short of coin). Presentation only — this drives the "starved"
  /// warning in the UI, and it must keep meaning *scarcity* and nothing else.
  double lastEfficiency = 1.0;

  /// Event throughput multiplier applied this tick. Transient, never saved.
  /// Kept separate from [lastEfficiency] so a gale does not make the
  /// "short on input" warning lie.
  double eventThrottle = 1.0;

  /// Output produced but not yet carted to the stores.
  ///
  /// A shed fills its own yard and waits for you. Nothing is ever lost — once
  /// the yard is full the shed simply idles, exactly as it does when its input
  /// runs dry — so a player who does not tap for an hour is slowed, never
  /// punished, and there is nothing to sell them to make it go away.
  final Map<Resource, double> hold = {};

  double get holdTotal => hold.values.fold(0.0, (s, v) => s + v);

  /// How much of one output this yard can stack up before the shed idles.
  double holdCapOf(Resource r) {
    final per = def.outputs[r] ?? 0;
    if (per <= 0) return 0;
    return per * def.maxWorkers * kHoldTicks * yardBonus;
  }

  /// Multiplier on this yard's capacity, from the warehouses you have built.
  /// Transient: recomputed from the port every tick, never serialised.
  double yardBonus = 1.0;

  /// 0..1 across every output — what the yard indicator shows.
  double get holdFullness {
    if (def.outputs.isEmpty) return 0;
    var worst = 0.0;
    def.outputs.forEach((r, _) {
      final cap = holdCapOf(r);
      if (cap > 0) {
        final f = ((hold[r] ?? 0) / cap).clamp(0.0, 1.0);
        if (f > worst) worst = f;
      }
    });
    return worst;
  }

  bool get hasCollectableOutput => holdTotal > 0.5;

  Map<String, dynamic> toJson() => {
        'defId': defId,
        'workers': workers,
        'col': col,
        'row': row,
        if (hold.isNotEmpty)
          'hold': hold.map((k, v) =>
              MapEntry(k.name, double.parse(v.toStringAsFixed(3)))),
        if (def.imports) 'import': importResource.name,
      };

  static Building fromJson(Map<String, dynamic> j) {
    Resource? imported;
    final raw = j['import'];
    if (raw is String) {
      try {
        final r = Resource.byId(raw);
        if (kImportables.contains(r)) imported = r;
      } on StateError {
        // Resource retired since the save was written; fall back to default.
      }
    }
    final b = Building(
      defId: j['defId'] as String,
      workers: (j['workers'] as num).toInt(),
      importResource: imported,
      // Absent in a pre-map save; the port lays itself out on load.
      col: (j['col'] as num?)?.toInt() ?? -1,
      row: (j['row'] as num?)?.toInt() ?? -1,
    );
    final held = j['hold'];
    if (held is Map<String, dynamic>) {
      held.forEach((k, v) {
        try {
          b.hold[Resource.byId(k)] = (v as num).toDouble();
        } on StateError {
          // Resource retired since the save was written.
        }
      });
    }
    return b;
  }
}
