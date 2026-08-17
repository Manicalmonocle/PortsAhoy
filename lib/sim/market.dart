import 'resources.dart';

/// Deterministic, serializable PRNG.
///
/// `dart:math`'s Random cannot be saved mid-stream, and a resumed game that
/// re-rolls its ship schedule feels broken. A tiny LCG keeps the world
/// reproducible across save/load and makes the economy tests deterministic.
class SeededRng {
  SeededRng(this.seed);
  int seed;

  /// A plain LCG modulo a power of two has famously weak low-order bits, and
  /// the game samples it at fixed strides — the town's growth roll happens
  /// once a day, always the same number of draws apart. Sampled that way the
  /// raw sequence is strongly correlated, which showed up in play as a town
  /// sitting at the same population for eleven days against a supposed 50%
  /// daily chance.
  ///
  /// The state advance is unchanged (full period, cheap, serialisable); the
  /// output is passed through an avalanche finalizer so every bit of state
  /// affects every bit of the result. Same determinism, no stride artefacts.
  double next() {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    var x = seed;
    x ^= x >> 15;
    x = (x * 0x2C1B3C6D) & 0x7FFFFFFF;
    x ^= x >> 12;
    x = (x * 0x297A2D39) & 0x7FFFFFFF;
    x ^= x >> 15;
    return x / 0x7FFFFFFF;
  }

  /// Uniform double in [min, max).
  double range(double min, double max) => min + next() * (max - min);

  /// Uniform int in [min, max] inclusive.
  int rangeInt(int min, int max) => min + (next() * (max - min + 1)).floor().clamp(0, max - min);

  T pick<T>(List<T> items) => items[rangeInt(0, items.length - 1)];
}

const List<String> _shipPrefix = [
  'Grey', 'Salt', 'North', 'Iron', 'Long', 'Storm', 'Fair', 'Red', 'Cold', 'Bright',
];
const List<String> _shipSuffix = [
  'Gull', 'Petrel', 'Lantern', 'Compass', 'Herring', 'Anchor', 'Wake', 'Mariner',
  'Current', 'Harbour',
];

/// One line item on a ship's manifest: it will buy up to [quantity] units of
/// [resource] at [pricePerUnit] coin.
class Offer {
  Offer({required this.resource, required this.quantity, required this.pricePerUnit});

  final Resource resource;
  double quantity;
  final double pricePerUnit;

  bool get isFilled => quantity <= 1e-6;

  Map<String, dynamic> toJson() => {
        'r': resource.name,
        'q': quantity,
        'p': pricePerUnit,
      };

  static Offer fromJson(Map<String, dynamic> j) => Offer(
        resource: Resource.byId(j['r'] as String),
        quantity: (j['q'] as num).toDouble(),
        pricePerUnit: (j['p'] as num).toDouble(),
      );
}

/// Contraband in, materials out. The dark market's second face, and the reason
/// a smuggler can supply their sheds without ever touching coin.
class Barter {
  Barter({
    required this.give,
    required this.giveQty,
    required this.take,
    required this.takeQty,
  });

  /// What the captain wants from you (always contraband).
  final Resource give;
  final double giveQty;

  /// What they will land in exchange.
  final Resource take;
  final double takeQty;

  bool taken = false;

  Map<String, dynamic> toJson() => {
        'g': give.name,
        'gq': giveQty,
        't': take.name,
        'tq': takeQty,
        'done': taken,
      };

  static Barter? fromJson(Map<String, dynamic> j) {
    try {
      return Barter(
        give: Resource.byId(j['g'] as String),
        giveQty: (j['gq'] as num).toDouble(),
        take: Resource.byId(j['t'] as String),
        takeQty: (j['tq'] as num).toDouble(),
      )..taken = j['done'] as bool? ?? false;
    } on StateError {
      return null; // resource retired since the save was written
    }
  }
}

class Ship {
  Ship({
    required this.name,
    required this.departTick,
    required this.offers,
    List<Offer>? wares,
    List<Barter>? barters,
    this.allegiance = 'crown',
    this.foreign = false,
    this.prizeTons = 0,
  })  : wares = wares ?? [],
        barters = barters ?? [];

  /// Sails under another flag, and is therefore a lawful target for a port
  /// holding a Letter of Marque. Your own Crown's traders never are.
  final bool foreign;

  /// Tonnage in her hold, if boarded.
  final int prizeTons;

  final String name;
  final int departTick;

  /// 'crown' — an honest trader who deals only in legitimate goods and whose
  /// prices shade down as your reputation worsens. 'free' — a free trader who
  /// buys contraband, barters it for materials, and never asks questions.
  final String allegiance;

  bool get isFreeTrader => allegiance == 'free';

  /// Contraband-for-materials swaps, free traders only.
  final List<Barter> barters;

  /// What this captain will buy from you.
  final List<Offer> offers;

  /// What this captain will sell you, at a markup over the going rate.
  ///
  /// Without this the port is a one-way valve: coin piles up with nothing to
  /// spend it on but buildings, and a player who sells their plank stock down
  /// can be permanently unable to build their way out of it.
  final List<Offer> wares;

  bool get isSpent =>
      offers.every((o) => o.isFilled) &&
      wares.every((w) => w.isFilled) &&
      barters.every((b) => b.taken);

  Map<String, dynamic> toJson() => {
        'name': name,
        'departTick': departTick,
        'al': allegiance,
        'foreign': foreign,
        'pt': prizeTons,
        'offers': offers.map((o) => o.toJson()).toList(),
        'wares': wares.map((w) => w.toJson()).toList(),
        'bt': barters.map((b) => b.toJson()).toList(),
      };

  static Ship fromJson(Map<String, dynamic> j) => Ship(
        name: j['name'] as String,
        departTick: (j['departTick'] as num).toInt(),
        // Every ship in a v1 save deserialises as an honest Crown trader,
        // which is exactly right for a port that never ran contraband.
        allegiance: j['al'] as String? ?? 'crown',
        foreign: j['foreign'] as bool? ?? false,
        prizeTons: (j['pt'] as num?)?.toInt() ?? 0,
        offers: (j['offers'] as List)
            .map((o) => Offer.fromJson(o as Map<String, dynamic>))
            .toList(),
        wares: (j['wares'] as List? ?? [])
            .map((w) => Offer.fromJson(w as Map<String, dynamic>))
            .toList(),
        barters: (j['bt'] as List? ?? [])
            .map((b) => Barter.fromJson(b as Map<String, dynamic>))
            .whereType<Barter>()
            .toList(),
      );
}

/// The port's price environment.
///
/// Every resource carries an index that mean-reverts toward 1.0. Selling in
/// bulk pushes an index down, so dumping 200 rope in one afternoon tanks rope
/// for days. That single feedback loop is what makes diversifying the port
/// pay better than optimising one chain, and it replaces the "wait or pay"
/// pressure that a free-to-play economy would use here.
/// Conditions the wider world imposes on this port.
///
/// Declared here rather than in events.dart so market.dart keeps importing
/// nothing but resources.dart. Events fold themselves down into one of these
/// each tick and hand it over; the market never knows what an event is.
class PortConditions {
  const PortConditions({
    this.shipsBlocked = false,
    this.arrivalInterval = Market.shipCheckInterval,
    this.maxShips = Market.maxShipsInPort,
    this.demandScale = 1.0,
    this.indexTarget = const {},
  });

  /// No new ship may make the quay.
  final bool shipsBlocked;

  final int arrivalInterval;
  final int maxShips;

  /// Multiplier on what arriving captains will pay.
  final double demandScale;

  /// Prices the wider world is pulling toward while this lasts — a blockade
  /// bidding planks up, a glut driving rope down. The pull is stronger than
  /// the standing mean reversion, so the shock wins while it is on and prices
  /// walk home on their own once it lifts.
  final Map<Resource, double> indexTarget;

  static const calm = PortConditions();
}

class Market {
  Market({Map<Resource, double>? index, List<Ship>? ships})
      : index = index ?? {for (final r in Resource.values) r: 1.0},
        ships = ships ?? [];

  final Map<Resource, double> index;
  final List<Ship> ships;

  static const double minIndex = 0.45;

  /// Headroom above the old 1.90 ceiling so a blockade or a piracy scare has
  /// somewhere to push a price to.
  static const double maxIndex = 2.40;
  static const double reversionRate = 0.005;

  /// How hard an active event drags a price toward its target. An order of
  /// magnitude above [reversionRate] so the world outranks the equilibrium
  /// while the event is on, and loses to it the moment the event lifts.
  static const double eventPullRate = 0.06;

  /// How many units it takes to meaningfully move a price.
  static const double saleImpactScale = 900.0;

  static const int shipCheckInterval = 18;
  static const int maxShipsInPort = 4;

  double priceOf(Resource r) => r.basePrice * (index[r] ?? 1.0);

  /// Share of arrivals that are free traders, once the dark trade is open.
  static const double freeTraderShare = 0.34;

  /// The dark market is thin, so it moves further on less volume.
  static const double contrabandImpactScale = 300.0;

  void advance(
    int tick,
    SeededRng rng, [
    PortConditions conditions = PortConditions.calm,
    bool darkTradeOpen = false,
    double notoriety = 0.0,
  ]) {
    for (final r in Resource.values) {
      final cur = index[r] ?? 1.0;
      var next = cur + (1.0 - cur) * reversionRate + (rng.next() - 0.5) * 0.004;

      // An exogenous shock: the world, not the player, moving a price.
      final target = conditions.indexTarget[r];
      if (target != null) next += (target - next) * eventPullRate;

      index[r] = next.clamp(minIndex, maxIndex);
    }

    ships.removeWhere((s) => tick >= s.departTick || s.isSpent);

    if (!conditions.shipsBlocked &&
        tick % conditions.arrivalInterval == 0 &&
        ships.length < conditions.maxShips) {
      final free = darkTradeOpen && rng.next() < freeTraderShare;
      ships.add(free
          ? _rollFreeTrader(tick, rng, notoriety)
          : _rollShip(
              tick, rng, conditions.demandScale, notoriety, darkTradeOpen));
    }
  }

  /// A captain who asks no questions.
  ///
  /// Both of their channels get worse as notoriety climbs: they bid less for
  /// your contraband and want more of it per unit of cargo. There is
  /// deliberately no reputation level that is simply good — heat is a cost on
  /// every side, never a faucet.
  Ship _rollFreeTrader(int tick, SeededRng rng, double notoriety) {
    final shade = (1.0 - notoriety * 0.0035).clamp(0.55, 1.0);

    final bids = Resource.contraband.map((r) {
      return Offer(
        resource: r,
        quantity: rng.range(25, 70).roundToDouble(),
        pricePerUnit: double.parse(
            (r.basePrice * (index[r] ?? 1.0) * rng.range(0.95, 1.35) * shade)
                .toStringAsFixed(2)),
      );
    }).toList();

    // Contraband for raw materials, at a parity coin cannot match in bulk.
    const takePool = [
      Resource.ore,
      Resource.timber,
      Resource.flax,
      Resource.grain,
      Resource.planks,
    ];

    // Spice buys what nothing else can shortcut.
    //
    // Raws were never the bottleneck: the lighthouse wants 80 tools, 120 rope
    // and 90 sailcloth, and a swap that lands ore still needs the sheds and
    // the hands to turn it into any of those. That is why the dark trade
    // measured as a trap — it paid in the one thing the port already had.
    // Spice is taken off a hull rather than made, so it is the one currency
    // that can buy finished work.
    const spiceTakePool = [
      Resource.tools,
      Resource.rope,
      Resource.sailcloth,
    ];

    final barters = <Barter>[];
    final swaps = rng.rangeInt(1, 2);
    for (var i = 0; i < swaps; i++) {
      final give = Resource.contraband[rng.rangeInt(0, Resource.contraband.length - 1)];
      final pool = give == Resource.spice ? spiceTakePool : takePool;
      final take = pool[rng.rangeInt(0, pool.length - 1)];
      // Finished goods move in smaller lots than bulk raws — a hull does not
      // carry 160 tools — and the quantity is what sets how much of a run a
      // single swap can shorten.
      final takeQty = give == Resource.spice
          ? rng.range(25, 60).roundToDouble()
          : rng.range(60, 160).roundToDouble();
      final parity = rng.range(1.25, 1.70) * shade;
      final giveQty =
          (takeQty * take.basePrice) / (give.basePrice * parity);
      barters.add(Barter(
        give: give,
        giveQty: double.parse(giveQty.toStringAsFixed(1)),
        take: take,
        takeQty: takeQty,
      ));
    }

    return Ship(
      name: '${rng.pick(_shipPrefix)} ${rng.pick(_shipSuffix)}',
      departTick: tick + rng.rangeInt(24, 56),
      allegiance: 'free',
      offers: bids,
      barters: barters,
    );
  }

  /// Share of ordinary arrivals flying a foreign flag, once the dark trade is
  /// open. Zero before that, so an honest port never sees a target.
  static const double foreignShipChance = 0.30;

  Ship _rollShip(int tick, SeededRng rng,
      [double demandScale = 1.0,
      double notoriety = 0.0,
      bool darkTradeOpen = false]) {
    // Ships favour finished goods — that is the pull toward refining.
    // An honest captain will not touch contraband at any price.
    final legit =
        Resource.values.where((r) => !r.isContraband).toList(growable: false);
    final pool = <Resource>[
      ...legit.where((r) => r.category == ResourceCategory.good),
      ...legit.where((r) => r.category == ResourceCategory.good),
      ...legit.where((r) => r.category != ResourceCategory.good),
    ];

    final count = rng.rangeInt(2, 4);
    final chosen = <Resource>{};
    for (var i = 0; i < count * 3 && chosen.length < count; i++) {
      chosen.add(pool[rng.rangeInt(0, pool.length - 1)]);
    }

    // Respectable captains discount a watched quay.
    final shade = (1.0 - notoriety * 0.0030).clamp(0.70, 1.0);

    final offers = chosen.map((r) {
      // 0.85–1.40 of the prevailing index: some captains overpay, some lowball.
      final demand = rng.range(0.85, 1.40) * demandScale * shade;
      return Offer(
        resource: r,
        quantity: rng.range(20, 80).roundToDouble(),
        pricePerUnit:
            double.parse((r.basePrice * (index[r] ?? 1.0) * demand).toStringAsFixed(2)),
      );
    }).toList();

    // Most captains arrive with cargo to shift. Raw materials mostly, so buying
    // is a way to unblock a chain rather than a way to skip playing it.
    final wareCount = rng.rangeInt(0, 2);
    final warePool = <Resource>[
      ...legit.where((r) => r.category != ResourceCategory.good),
      Resource.planks,
    ];
    final wares = <Offer>[];
    final chosenWares = <Resource>{};
    for (var i = 0; i < wareCount * 3 && chosenWares.length < wareCount; i++) {
      chosenWares.add(warePool[rng.rangeInt(0, warePool.length - 1)]);
    }
    for (final r in chosenWares) {
      final markup = rng.range(1.10, 1.55);
      wares.add(Offer(
        resource: r,
        quantity: rng.range(20, 70).roundToDouble(),
        pricePerUnit:
            double.parse((r.basePrice * (index[r] ?? 1.0) * markup).toStringAsFixed(2)),
      ));
    }

    // Once the dark trade is open, some arrivals fly another flag — and a
    // foreign hull with cargo in her is a lawful prize if you hold a Letter.
    final foreign = darkTradeOpen && rng.next() < foreignShipChance;

    return Ship(
      name: '${rng.pick(_shipPrefix)} ${rng.pick(_shipSuffix)}',
      departTick: tick + rng.rangeInt(30, 70),
      offers: offers,
      wares: wares,
      foreign: foreign,
      prizeTons: foreign ? rng.rangeInt(30, 90) : 0,
    );
  }

  /// Record that [qty] units of [r] hit the market, depressing its price.
  void applySalePressure(Resource r, double qty) {
    final cur = index[r] ?? 1.0;
    index[r] = (cur * (1.0 - qty / saleImpactScale)).clamp(minIndex, maxIndex);
  }

  /// Record that [qty] units of [r] were bought out of the market, lifting it.
  void applyPurchasePressure(Resource r, double qty) {
    final cur = index[r] ?? 1.0;
    index[r] = (cur * (1.0 + qty / saleImpactScale)).clamp(minIndex, maxIndex);
  }

  Map<String, dynamic> toJson() => {
        'index': index.map((k, v) => MapEntry(k.name, double.parse(v.toStringAsFixed(4)))),
        'ships': ships.map((s) => s.toJson()).toList(),
      };

  static Market fromJson(Map<String, dynamic> j) {
    final idx = {for (final r in Resource.values) r: 1.0};
    (j['index'] as Map<String, dynamic>).forEach((k, v) {
      try {
        idx[Resource.byId(k)] = (v as num).toDouble();
      } on StateError {
        // Unknown resource from an older save.
      }
    });
    return Market(
      index: idx,
      ships: (j['ships'] as List)
          .map((s) => Ship.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
