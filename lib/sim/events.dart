/// The weather, the water, and the wider world.
///
/// Pure data plus a small scheduler, following the `kBuildingDefs` idiom. The
/// design rule that governs everything here: **duration, magnitude and target
/// are all rolled once, at draw time, and stored**. That is what lets the omen
/// tell the player exactly what is coming and for exactly how long, and what
/// stops a save reloaded mid-omen from quietly rerolling the outcome.
/// Forewarning that lies is worse than no forewarning at all.
library;

import 'market.dart';
import 'resources.dart';

enum EventSeverity { minor, major, boon }

class EventDef {
  const EventDef({
    required this.id,
    required this.name,
    required this.icon,
    required this.severity,
    required this.blurb,
    required this.omenLine,
    required this.onsetLine,
    required this.liftLine,
    required this.minDays,
    required this.maxDays,
    this.omenTicks = 24,
    this.seasonWeight = const {0: 1.0, 1: 1.0, 2: 1.0, 3: 1.0},
    this.minDay = 1,
    this.minBuildings = 0,
    this.requiresBuildingId,
    this.throughput = const {},
    this.yieldScale = const {},
    this.onsetStockScale = const {},
    this.onsetStockGrant = const {},
    this.onsetCoinScale = 1.0,
    this.indexTarget = const {},
    this.targetsAGood = false,
    this.targetIndex = 1.0,
    this.absentFraction = 0.0,
    this.foodScale = 1.0,
    this.wageScale = 1.0,
    this.shipsBlocked = false,
    this.arrivalInterval,
    this.maxShips,
    this.demandScale = 1.0,
  });

  final String id;
  final String name;
  final String icon;
  final EventSeverity severity;

  /// Shown on the active-event card.
  final String blurb;

  /// Log lines for the three moments: forewarning, arrival, and passing.
  final String omenLine;
  final String onsetLine;
  final String liftLine;

  final int minDays;
  final int maxDays;

  /// Game-hours of forewarning before the event actually bites.
  final int omenTicks;

  /// Season index (0 spring … 3 winter) to relative weight. A season absent
  /// from this map means the event cannot happen then at all — which is what
  /// makes the world learnable instead of a dice bag.
  final Map<int, double> seasonWeight;

  final int minDay;
  final int minBuildings;
  final String? requiresBuildingId;

  /// Multiplier on *effective workers* by building id, or '*' for every shed.
  /// The shed works slower: inputs and outputs both scale.
  final Map<String, double> throughput;

  /// Multiplier on *output only* by building id. Inputs are consumed in full
  /// and the difference is destroyed — which is what spoiled flax and a fouled
  /// saw blade actually are.
  final Map<String, double> yieldScale;

  /// One-off multiplier applied to stock the moment the event lands.
  final Map<Resource, double> onsetStockScale;

  /// One-off gift of stock at onset (salvage).
  final Map<Resource, double> onsetStockGrant;

  /// One-off multiplier on the treasury at onset (a levy).
  final double onsetCoinScale;

  /// Prices the world pulls toward for the duration.
  final Map<Resource, double> indexTarget;

  /// When true, one finished good is chosen at draw time and [targetIndex] is
  /// applied to it — so a glut hits a different trade each time it happens.
  final bool targetsAGood;
  final double targetIndex;

  /// Fraction of the working population laid up.
  final double absentFraction;

  /// Multiplier on what the town eats per head per day.
  final double foodScale;

  /// Multiplier on the daily wage bill.
  final double wageScale;

  final bool shipsBlocked;
  final int? arrivalInterval;
  final int? maxShips;
  final double demandScale;

  bool get isHazard => severity != EventSeverity.boon;
}

/// One scheduled instance of an [EventDef].
class ActiveEvent {
  ActiveEvent({
    required this.defId,
    required this.omenTick,
    required this.startTick,
    required this.endTick,
    this.absentCount = 0,
    this.target,
  });

  final String defId;
  final int omenTick;
  final int startTick;

  /// Written once at draw time; read-only thereafter.
  final int endTick;

  /// Headcount only — never a per-building assignment, so a fever cannot be
  /// dodged by shuffling hands between sheds.
  final int absentCount;

  /// Resolved at draw time for [EventDef.targetsAGood].
  final Resource? target;

  EventDef get def => eventById(defId);

  bool isOmen(int tick) => tick < startTick;
  bool isActive(int tick) => tick >= startTick && tick < endTick;

  Map<String, dynamic> toJson() => {
        'defId': defId,
        'omenTick': omenTick,
        'startTick': startTick,
        'endTick': endTick,
        'absentCount': absentCount,
        if (target != null) 'target': target!.name,
      };

  static ActiveEvent? fromJson(Map<String, dynamic> j) {
    final id = j['defId'] as String;
    if (!kEventDefs.any((d) => d.id == id)) return null; // retired event
    Resource? t;
    final raw = j['target'];
    if (raw is String) {
      try {
        t = Resource.byId(raw);
      } on StateError {
        t = null;
      }
    }
    return ActiveEvent(
      defId: id,
      omenTick: (j['omenTick'] as num).toInt(),
      startTick: (j['startTick'] as num).toInt(),
      endTick: (j['endTick'] as num).toInt(),
      absentCount: (j['absentCount'] as num?)?.toInt() ?? 0,
      target: t,
    );
  }
}

/// The folded per-tick snapshot of everything currently in force. Transient —
/// recomputed every tick and never serialised, so it can never disagree with
/// the active list.
class EventEffects {
  EventEffects();

  final Map<String, double> throughput = {};
  final Map<String, double> yieldScale = {};
  double foodScale = 1.0;
  double wageScale = 1.0;
  int absentTotal = 0;
  PortConditions conditions = PortConditions.calm;

  double throughputFor(String id) =>
      (throughput['*'] ?? 1.0) * (throughput[id] ?? 1.0);
  double yieldFor(String id) => yieldScale[id] ?? 1.0;

  bool get isCalm =>
      throughput.isEmpty &&
      yieldScale.isEmpty &&
      absentTotal == 0 &&
      foodScale == 1.0 &&
      wageScale == 1.0;
}

EventDef eventById(String id) => kEventDefs.firstWhere((d) => d.id == id);

/// Tuning for the scheduler itself.
class EventTuning {
  /// Days before anything at all can happen — the tutorial the game does not
  /// otherwise have.
  static const int graceDays = 12;

  /// A 120-day year, so a median run sees two winters.
  static const int seasonLengthDays = 30;

  /// Quiet days owed after an event ends, by severity, measured from its END —
  /// which is what stops long events stacking into a permanent siege.
  static const int recoveryMajor = 2;
  static const int recoveryMinor = 1;
  static const int recoveryBoon = 1;

  /// Days a roll defers when a hazard is already on station.
  static const int deferDays = 2;

  /// Quiet days between events, keyed on how much port there is to disrupt.
  ///
  /// Stage is CAPACITY, not calendar: a careful slow player is never punished
  /// for taking their time, and a player who throws up twenty sheds gets the
  /// weather they asked for.
  static const List<int> gapTierBuildings = [8, 13];
  static const List<int> gapLowDays = [6, 4, 3];
  static const List<int> gapHighDays = [10, 8, 6];

  static int gapTier(int buildableCount) {
    for (var i = 0; i < gapTierBuildings.length; i++) {
      if (buildableCount <= gapTierBuildings[i]) return i;
    }
    return gapTierBuildings.length;
  }

  /// How many past events the repeat guard remembers.
  static const int historyDepth = 8;

  /// An event may not repeat while it sits in the most recent N of history.
  static const int repeatGuard = 2;

  /// Severity scaling. Below [pressureFloorSheds] the world is as gentle as it
  /// always was; by [pressureFullSheds] every hazard bites [maxPressure] times
  /// as hard and lasts longer.
  static const int pressureFloorSheds = 6;
  static const int pressureFullSheds = 22;
  static const double maxPressure = 2.4;

  /// A shed is never taken below this, however hard the world pushes — a
  /// setback should cost you a stretch of output, never brick the port.
  static const double severityFloor = 0.12;

  /// Above this pressure a second hazard may run alongside the first. A large
  /// port can weather two things at once; a small one cannot.
  static const double twoHazardPressure = 1.75;

  /// Mercy floors: a port already on the floor never gets kicked.
  static const int mercyPopulation = 4;
  static const double mercyWageDays = 2.0;
  static const double mercyFoodDays = 1.5;
}

/// Everything the scheduler needs to know about the port, passed in explicitly
/// so this file never has to import game_state.dart.
class EventContext {
  const EventContext({
    required this.day,
    required this.buildableCount,
    required this.population,
    required this.assignedWorkers,
    required this.foodDays,
    required this.coin,
    required this.dailyWageBill,
    required this.buildingIds,
    this.producingSheds = 0,
    this.hazardGap = 1.0,
  });

  final int day;
  final int buildableCount;
  final int population;
  final int assignedWorkers;
  final double foodDays;
  final int coin;
  final int dailyWageBill;
  final Set<String> buildingIds;

  /// Producing sheds — the honest measure of how much port there is.
  final int producingSheds;

  /// Multiplier on the quiet days between events, from active charters.
  final double hazardGap;

  int get season =>
      ((day - 1) ~/ EventTuning.seasonLengthDays) % 4;

  /// How hard the world should push, 1.0 at a small port rising to
  /// [EventTuning.maxPressure] at a large one.
  ///
  /// Fixed severity is why a well-run port stopped noticing the weather: a
  /// third off one shed is a crisis on day 10 and rounding error on day 100.
  /// Mercy floors still protect a struggling port — this only sharpens the
  /// deck against one that is thriving.
  double get pressure {
    final t = ((producingSheds - EventTuning.pressureFloorSheds) /
            (EventTuning.pressureFullSheds - EventTuning.pressureFloorSheds))
        .clamp(0.0, 1.0);
    return 1.0 + t * (EventTuning.maxPressure - 1.0);
  }
}

/// What changed this tick, so the caller can apply one-off effects and log.
class EventTransitions {
  const EventTransitions(this.started, this.ended);
  final List<ActiveEvent> started;
  final List<ActiveEvent> ended;
  bool get isEmpty => started.isEmpty && ended.isEmpty;
}

class EventSystem {
  EventSystem({
    int? nextRollTick,
    List<ActiveEvent>? active,
    List<String>? history,
  })  : nextRollTick =
            nextRollTick ?? EventTuning.graceDays * 24,
        active = active ?? [],
        history = history ?? [];

  int nextRollTick;
  final List<ActiveEvent> active;
  final List<String> history;

  EventEffects effects = EventEffects();

  /// Set by the caller each tick; folded into every severity.
  double pressure = 1.0;

  /// Events currently biting (as opposed to merely forewarned).
  Iterable<ActiveEvent> live(int tick) => active.where((e) => e.isActive(tick));

  /// Events forewarned but not yet begun.
  Iterable<ActiveEvent> omens(int tick) => active.where((e) => e.isOmen(tick));

  bool hazardPending(int tick) =>
      active.any((e) => e.def.isHazard && tick < e.endTick);

  /// Expire, begin, and refold. **Draws no randomness whatsoever**, which is
  /// what keeps a save resumed mid-event on the identical world line.
  EventTransitions advance(int tick, {double pressure = 1.0}) {
    this.pressure = pressure;
    final started = <ActiveEvent>[];
    final ended = <ActiveEvent>[];

    for (final e in List.of(active)) {
      if (tick == e.startTick) started.add(e);
      if (tick >= e.endTick) {
        ended.add(e);
        active.remove(e);
        history.add(e.defId);
        while (history.length > EventTuning.historyDepth) {
          history.removeAt(0);
        }
      }
    }

    _fold(tick);
    return EventTransitions(started, ended);
  }

  void _fold(int tick) {
    final fx = EventEffects();
    var shipsBlocked = false;
    var demand = 1.0;
    final targets = <Resource, double>{};

    final hazardIntervals = <int>[];
    final boonIntervals = <int>[];
    final hazardShips = <int>[];
    final boonShips = <int>[];

    for (final e in live(tick)) {
      final d = e.def;
      // A penalty of 0.7 (30% off) becomes 0.28 at full pressure. Boons are
      // left alone: making good weather better is not the problem.
      double sharpen(double v) => v >= 1.0
          ? v
          : (1.0 - (1.0 - v) * pressure).clamp(EventTuning.severityFloor, 1.0);

      d.throughput.forEach((k, v) =>
          fx.throughput[k] = (fx.throughput[k] ?? 1.0) * sharpen(v));
      d.yieldScale.forEach((k, v) =>
          fx.yieldScale[k] = (fx.yieldScale[k] ?? 1.0) * sharpen(v));
      fx.foodScale *= d.foodScale;
      fx.wageScale *= d.wageScale;
      fx.absentTotal += e.absentCount;

      shipsBlocked = shipsBlocked || d.shipsBlocked;
      demand *= d.demandScale;
      d.indexTarget.forEach((r, v) => targets[r] = v);
      if (d.targetsAGood && e.target != null) {
        targets[e.target!] = d.targetIndex;
      }

      if (d.arrivalInterval != null) {
        (d.isHazard ? hazardIntervals : boonIntervals).add(d.arrivalInterval!);
      }
      if (d.maxShips != null) {
        (d.isHazard ? hazardShips : boonShips).add(d.maxShips!);
      }
    }

    // A hazard's restriction outranks a boon's generosity, so "the convoy came
    // in the day after the gale" cannot conjure ships through a closed sound.
    final interval = hazardIntervals.isNotEmpty
        ? hazardIntervals.reduce((a, b) => a > b ? a : b)
        : (boonIntervals.isNotEmpty
            ? boonIntervals.reduce((a, b) => a < b ? a : b)
            : Market.shipCheckInterval);
    final ships = hazardShips.isNotEmpty
        ? hazardShips.reduce((a, b) => a < b ? a : b)
        : (boonShips.isNotEmpty
            ? boonShips.reduce((a, b) => a > b ? a : b)
            : Market.maxShipsInPort);

    fx.conditions = PortConditions(
      shipsBlocked: shipsBlocked,
      arrivalInterval: interval,
      maxShips: ships,
      demandScale: demand,
      indexTarget: targets,
    );
    effects = fx;
  }

  /// The ONLY place this system consumes randomness. Called once per day.
  ///
  /// Returns the event drawn, or null. The caller logs the omen line.
  ActiveEvent? rollAtDayEnd(int tick, SeededRng rng, EventContext ctx) {
    if (tick < nextRollTick) return null;

    // One hazard at a time — until the port is big enough to take two.
    final hazardCap = ctx.pressure >= EventTuning.twoHazardPressure ? 2 : 1;
    final livingHazards =
        active.where((e) => e.def.isHazard && tick < e.endTick).length;
    if (livingHazards >= hazardCap) {
      nextRollTick = tick + EventTuning.deferDays * 24;
      return null;
    }

    final pool = <EventDef>[];
    final weights = <double>[];
    for (final d in kEventDefs) {
      final w = _weightFor(d, ctx);
      if (w > 0) {
        pool.add(d);
        weights.add(w);
      }
    }
    if (pool.isEmpty) {
      nextRollTick = tick + EventTuning.deferDays * 24;
      return null;
    }

    final total = weights.reduce((a, b) => a + b);
    var pick = rng.next() * total;
    var chosen = pool.last;
    for (var i = 0; i < pool.length; i++) {
      pick -= weights[i];
      if (pick <= 0) {
        chosen = pool[i];
        break;
      }
    }

    var days = chosen.minDays == chosen.maxDays
        ? chosen.minDays
        : rng.rangeInt(chosen.minDays, chosen.maxDays);
    // Hazards also run longer against a big port; boons do not.
    if (chosen.isHazard) {
      days = (days * (1 + (ctx.pressure - 1) * 0.45)).round();
    }
    final start = tick + chosen.omenTicks;

    // Absence is a headcount fixed at draw time, not a live fraction, so the
    // omen can state it truthfully and it cannot be dodged by reshuffling.
    final absent = chosen.absentFraction <= 0
        ? 0
        : (ctx.assignedWorkers *
                (chosen.absentFraction * (1 + (ctx.pressure - 1) * 0.35))
                    .clamp(0.0, 0.6))
            .round()
            .clamp(0, ctx.assignedWorkers);

    Resource? target;
    if (chosen.targetsAGood) {
      final goods = Resource.values
          .where((r) => r.category == ResourceCategory.good)
          .toList();
      target = goods[rng.rangeInt(0, goods.length - 1)];
    }

    final ev = ActiveEvent(
      defId: chosen.id,
      omenTick: tick,
      startTick: start,
      endTick: start + days * 24,
      absentCount: absent,
      target: target,
    );
    active.add(ev);

    final recovery = switch (chosen.severity) {
      EventSeverity.major => EventTuning.recoveryMajor,
      EventSeverity.minor => EventTuning.recoveryMinor,
      EventSeverity.boon => EventTuning.recoveryBoon,
    };
    // Measured from the END of this event, which is what stops long events
    // stacking into a permanent siege.
    final tier = EventTuning.gapTier(ctx.buildableCount);
    final gap = rng.rangeInt(
        EventTuning.gapLowDays[tier], EventTuning.gapHighDays[tier]);
    // A charter can widen or narrow the quiet stretch between events. Never
    // below a day, or an omen would land on top of the event it warns about.
    final scaled = ((recovery + gap) * ctx.hazardGap).round().clamp(1, 400);
    nextRollTick = ev.endTick + scaled * 24;

    return ev;
  }

  double _weightFor(EventDef d, EventContext ctx) {
    if (ctx.day < d.minDay) return 0;
    if (ctx.buildableCount < d.minBuildings) return 0;
    if (d.requiresBuildingId != null &&
        !ctx.buildingIds.contains(d.requiresBuildingId)) {
      return 0;
    }

    final w = d.seasonWeight[ctx.season];
    if (w == null || w <= 0) return 0;

    // Repeat guard: not one of the most recent few.
    final recent = history.length <= EventTuning.repeatGuard
        ? history
        : history.sublist(history.length - EventTuning.repeatGuard);
    if (recent.contains(d.id)) return 0;

    // Mercy floors apply to hazards only, so the deck is at its most generous
    // exactly when things are worst.
    if (d.isHazard) {
      if (ctx.population <= EventTuning.mercyPopulation) return 0;
      if (ctx.coin < ctx.dailyWageBill * EventTuning.mercyWageDays) return 0;
      if (ctx.foodDays < EventTuning.mercyFoodDays) return 0;
    }
    return w;
  }

  Map<String, dynamic> toJson() => {
        'nextRollTick': nextRollTick,
        'active': active.map((e) => e.toJson()).toList(),
        'history': history,
      };

  static EventSystem fromJson(Map<String, dynamic>? j) {
    if (j == null) return EventSystem();
    return EventSystem(
      nextRollTick: (j['nextRollTick'] as num?)?.toInt(),
      active: (j['active'] as List? ?? [])
          .map((e) => ActiveEvent.fromJson(e as Map<String, dynamic>))
          .whereType<ActiveEvent>()
          .toList(),
      history: (j['history'] as List? ?? []).cast<String>().toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// The catalogue
// ---------------------------------------------------------------------------

// Seasons: 0 spring, 1 summer, 2 autumn, 3 winter.

const List<EventDef> kEventDefs = [
  EventDef(
    id: 'north_easterly',
    name: 'A North-Easterly',
    icon: '🌬️',
    severity: EventSeverity.major,
    blurb: 'Nothing enters or leaves the harbour, and the boats stay drawn up.',
    omenLine: 'The glass is falling. The old hands are drawing the boats up.',
    onsetLine: 'The north-easterly came in hard. No sail will make the quay.',
    liftLine: 'The wind backed westerly overnight. The quay is open again.',
    minDays: 2,
    maxDays: 4,
    seasonWeight: {0: 1.0, 1: 0.4, 2: 2.0, 3: 2.5},
    minDay: 12,
    shipsBlocked: true,
    throughput: {'fishing_wharf': 0.30},
  ),
  EventDef(
    id: 'cold_snap',
    name: 'A Cold Snap',
    icon: '❄️',
    severity: EventSeverity.minor,
    blurb: 'Hard frost. The fields sulk and the town burns through its stores.',
    omenLine: 'Frost on the inside of the windows. It will be a hard week.',
    onsetLine: 'A cold snap has the fields locked. Everyone is eating more.',
    liftLine: 'The frost broke. The ground is workable again.',
    minDays: 2,
    maxDays: 3,
    seasonWeight: {2: 0.8, 3: 2.5},
    minDay: 12,
    throughput: {'farm': 0.55, 'fishing_wharf': 0.75},
    foodScale: 1.20,
  ),
  EventDef(
    id: 'the_shoals_moved',
    name: 'The Shoals Moved',
    icon: '🐟',
    severity: EventSeverity.major,
    blurb: 'The herring have gone somewhere else. Nobody knows where.',
    omenLine: 'Three boats came back light. The shoals may be shifting.',
    onsetLine: 'The shoals have moved off. The wharf is hauling empty nets.',
    liftLine: 'The herring are back on the bank.',
    minDays: 8,
    maxDays: 14,
    minDay: 20,
    requiresBuildingId: 'fishing_wharf',
    throughput: {'fishing_wharf': 0.30},
  ),
  EventDef(
    id: 'retting_rot',
    name: 'Rot in the Retting Pools',
    icon: '🌫️',
    severity: EventSeverity.major,
    blurb: 'The flax is going black in the water. Much of it will be waste.',
    omenLine: 'There is a smell off the retting pools that nobody likes.',
    onsetLine: 'Rot has the retting pools. Most of the crop will be waste.',
    liftLine: 'The pools have been dug out and refilled. Clean flax again.',
    minDays: 6,
    maxDays: 10,
    seasonWeight: {1: 2.0, 2: 2.0},
    minDay: 25,
    requiresBuildingId: 'flax_field',
    yieldScale: {'flax_field': 0.35},
    onsetStockScale: {Resource.flax: 0.60},
  ),
  EventDef(
    id: 'grey_fever',
    name: 'The Grey Fever',
    icon: '🤒',
    severity: EventSeverity.major,
    blurb: 'A third of the town is laid up. The sheds they worked stand idle.',
    omenLine: 'Two families are abed with a fever. It will go round.',
    onsetLine: 'The grey fever has the town. A third of your hands cannot work.',
    liftLine: 'The fever has passed. The town is back on its feet.',
    minDays: 4,
    maxDays: 7,
    seasonWeight: {0: 1.5, 2: 1.0, 3: 2.0},
    minDay: 30,
    absentFraction: 0.32,
  ),
  EventDef(
    id: 'the_sound_froze',
    name: 'The Sound Froze',
    icon: '🧊',
    severity: EventSeverity.major,
    blurb: 'Ice from headland to headland. Nothing moves, and timber is gold.',
    omenLine: 'Ice is making in the shallows. The sound may close entirely.',
    onsetLine: 'The sound has frozen over. No ship will reach us for days.',
    liftLine: 'The ice broke up on the ebb. The sound is open.',
    minDays: 5,
    maxDays: 9,
    // Winter only, and the heaviest weight in the catalogue: days 91-120 of
    // every year are a stretch the player can see coming thirty days out and
    // stockpile against. That is the difference between weather and a dice bag.
    seasonWeight: {3: 6.0},
    minDay: 40,
    shipsBlocked: true,
    throughput: {'forest_camp': 0.50, 'mine': 0.60},
    indexTarget: {Resource.planks: 1.85, Resource.timber: 1.70},
  ),
  EventDef(
    id: 'shed_fire',
    name: 'Fire in the Sheds',
    icon: '🔥',
    severity: EventSeverity.major,
    blurb: 'A lamp went over in the night. A quarter of the finished goods '
        'are ash.',
    omenLine: 'Someone has been careless with a lamp near the sheds.',
    onsetLine: 'Fire took a shed in the night. A quarter of the worked goods '
        'are gone.',
    liftLine: 'The burnt shed has been cleared away.',
    minDays: 1,
    maxDays: 1,
    minDay: 30,
    minBuildings: 8,
    onsetStockScale: {
      Resource.planks: 0.75,
      Resource.rope: 0.75,
      Resource.barrels: 0.75,
      Resource.sailcloth: 0.75,
    },
  ),
  EventDef(
    id: 'sawpit_jam',
    name: 'The Fouled Sawpit',
    icon: '🪚',
    severity: EventSeverity.minor,
    blurb: 'The blade is binding. Good timber is going to waste.',
    omenLine: 'The sawyers say the blade is running hot.',
    onsetLine: 'The sawpit has fouled. Timber is going in and sawdust is '
        'coming out.',
    liftLine: 'The saw has been reset and sharpened.',
    minDays: 1,
    maxDays: 2,
    minDay: 15,
    requiresBuildingId: 'sawmill',
    yieldScale: {'sawmill': 0.40},
  ),
  EventDef(
    id: 'glutted_market',
    name: 'A Glutted Market',
    icon: '📉',
    severity: EventSeverity.major,
    blurb: 'Word is every port on the coast is holding the same cargo.',
    omenLine: 'A factor says the coast is awash with one particular cargo.',
    onsetLine: 'The market is glutted. That trade is barely worth the freight.',
    liftLine: 'The glut has cleared and prices are finding their level.',
    minDays: 4,
    maxDays: 6,
    minDay: 25,
    targetsAGood: true,
    targetIndex: 0.50,
  ),
  EventDef(
    id: 'privateer_scare',
    name: 'Privateers in the Lanes',
    icon: '🏴‍☠️',
    severity: EventSeverity.major,
    blurb: 'Hulls are being taken off the headland. Freight has gone dear and '
        'few captains will risk the run.',
    omenLine: 'A collier came in shot about. There are privateers working the '
        'lanes.',
    onsetLine: 'Privateers are taking hulls off the headland. Imports have '
        'gone dear and the quay has gone quiet.',
    liftLine: 'A frigate swept the lanes. The trade is moving again.',
    minDays: 4,
    maxDays: 7,
    minDay: 30,
    arrivalInterval: 30,
    maxShips: 2,
    // Freight risk is priced into everything the port has to bring in.
    indexTarget: {
      Resource.timber: 1.80,
      Resource.flax: 1.80,
      Resource.ore: 1.85,
    },
  ),
  EventDef(
    id: 'crown_levy',
    name: 'The Assessor',
    icon: '📜',
    severity: EventSeverity.major,
    blurb: 'The Crown has assessed your port and taken its portion.',
    omenLine: "The Crown's assessor is working his way up the coast.",
    onsetLine: 'The assessor took the Crown\'s portion of your treasury.',
    liftLine: 'The assessor has moved on to the next harbour.',
    minDays: 1,
    maxDays: 1,
    minDay: 45,
    // Proportional, so it is a real cost to a rich port and barely a scratch on
    // a struggling one. It cannot bankrupt anybody.
    onsetCoinScale: 0.82,
  ),
  EventDef(
    id: 'hard_words',
    name: 'Hard Words on the Quay',
    icon: '😠',
    severity: EventSeverity.minor,
    blurb: 'The crews want more, and for now they are getting it.',
    omenLine: 'There is muttering on the quay about what the work is worth.',
    onsetLine: 'The crews have had hard words with you. Wages are up.',
    liftLine: 'The quay has settled. Wages are back to the old rate.',
    minDays: 2,
    maxDays: 3,
    minDay: 25,
    wageScale: 1.6,
  ),
  EventDef(
    id: 'southern_convoy',
    name: 'The Southern Convoy',
    icon: '⛵',
    severity: EventSeverity.boon,
    blurb: 'A convoy is in and every captain is buying.',
    omenLine: 'A convoy is expected within the day, and they are buying.',
    onsetLine: 'The southern convoy is in. The quay has never been busier.',
    liftLine: 'The convoy has sailed south.',
    minDays: 4,
    maxDays: 6,
    minDay: 20,
    maxShips: 6,
    arrivalInterval: 10,
    demandScale: 1.30,
  ),
  EventDef(
    id: 'fair_winds',
    name: 'Fair Winds',
    icon: '☀️',
    severity: EventSeverity.boon,
    blurb: 'Clear weather and long light. Everything goes a little easier.',
    omenLine: 'The glass is high and steady.',
    onsetLine: 'Fair winds and long light. Every shed is running sweetly.',
    liftLine: 'The weather has turned ordinary again.',
    minDays: 3,
    maxDays: 3,
    seasonWeight: {0: 1.5, 1: 2.5},
    minDay: 15,
    throughput: {'*': 1.20},
  ),
  EventDef(
    id: 'wreck_on_the_skerries',
    name: 'The Wreck on the Skerries',
    icon: '🪵',
    severity: EventSeverity.boon,
    blurb: 'A hull went onto the rocks. What washes in is yours.',
    omenLine: 'There were lights on the skerries in the night, and then none.',
    onsetLine: 'A wreck on the skerries. The salvage has been carted up '
        'to the sheds.',
    liftLine: 'The skerries have been picked clean.',
    minDays: 2,
    maxDays: 3,
    minDay: 25,
    onsetStockGrant: {
      Resource.timber: 90,
      Resource.planks: 45,
      Resource.rope: 25,
      Resource.sailcloth: 20,
    },
  ),
];
