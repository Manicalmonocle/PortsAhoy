import 'buildings.dart';
import 'charters.dart';
import 'journal.dart';
import 'events.dart';
import 'market.dart';
import 'progression.dart';
import 'resources.dart';
import 'retinue.dart';
import 'run_code.dart';
import 'terrain.dart';
import 'trade.dart';

/// Tuning constants. Everything the balance depends on lives here so the
/// economy can be retuned without hunting through the tick loop.
class Balance {
  static const int ticksPerDay = 24;
  static const double foodPerPersonPerDay = 1.0;
  static const int wagePerWorkerPerDay = 4;
  static const double baseStorage = 200.0;

  /// Extra yard capacity every warehouse grants each shed.
  static const double yardBonusPerWarehouse = 0.5;
  /// Roofs the port has before you build a single cottage — the
  /// harbourmaster's own house.
  ///
  /// Deliberately the same as a cottage. At 4 against a cottage's 5 every
  /// total landed one below the number a player predicts (9, 14, 49 rather
  /// than 10, 15, 50), which reads as an off-by-one bug every single time.
  /// Matching them makes the arithmetic obvious: five a roof, all the way up.
  static const int baseHousing = 5;

  /// A fed, housed town grows on roughly half of its well-supplied days.
  static const double growthChance = 0.5;

  /// Days of food the town wants in store before anyone new moves in.
  static const double growthFoodDays = 2.0;

  /// Chance an unpaid hand leaves on a given day, and the headcount below
  /// which nobody leaves at all. Together these stop an empty treasury from
  /// emptying the town.
  static const double wageLossChance = 0.3;
  static const int wageLossFloor = 4;

  /// The victory project.
  ///
  /// Deliberately demands one good from every chain rather than a big pile of
  /// coin. A pure coin goal collapses late — income compounds until the number
  /// is trivial and the last stretch is just waiting. Requiring rope *and*
  /// sailcloth also forces the flax decision to be answered "both, eventually",
  /// which is the most interesting way to end the game.
  static const int lighthouseCoin = 9000;
  static const Map<Resource, double> lighthouseCost = {
    Resource.planks: 160,
    Resource.tools: 80,
    Resource.rope: 120,
    Resource.sailcloth: 90,
  };

  /// Catch-up work is bounded so resuming after a long absence cannot hang the
  /// app. This is a compute guard, not a progress cap — see [GameState.catchUp].
  static const int maxCatchUpTicks = 20000;

  /// Whether the port keeps working while you are not playing.
  ///
  /// False, deliberately. A tick-based game that advances in your absence
  /// quietly makes closing the app a decision with consequences — the town
  /// eats, wages fall due, and a port left overnight can be found starved in
  /// the morning. That is the shape of the thing this project exists not to
  /// be, even when the intent behind it was generous.
  ///
  /// With this off, the world is exactly as you left it. Nothing is missed by
  /// being away, so nothing is gained by staying.
  static const bool progressWhileAway = false;

  // ---- The import berth (the coin sink) ---------------------------------

  /// Coin an import berth commits per worker per tick.
  static const double importCoinPerWorkerTick = 34.0;

  /// The factor's cut over the going market rate.
  static const double importMargin = 1.45;

  /// Days of wages a berth leaves untouched, so imports can never starve the
  /// payroll and spiral the town.
  static const double importWageCushionDays = 3.0;

  // ---- Notoriety and the Revenue ----------------------------------------
  //
  // The rule that governs this whole layer: notoriety rises ONLY from explicit
  // player actions, and there is NO coin path down. No bribe, no harbour due,
  // no fine-in-lieu. A player with 50,000 coin has exactly the options a player
  // with 50 coin has. There is also no passive decay, so there is nothing to
  // wait out — and therefore no wait that money could ever shorten.

  /// Below this, no inspection is ever rolled. Provably, not statistically.
  static const double patrolFloor = 12.0;

  static const double heatPerContrabandSold = 0.025;
  static const double heatPerBarterUnit = 0.075;
  static const double heatPerExposedUnitPerTick = 0.00035;
  static const double heatPerSeizure = 8.0;
  static const double heatCleanInspection = -4.0;

  /// Honest commerce launders. The smuggler's legitimate front is a real
  /// mechanic, so the ordinary chains stay load-bearing inside the risk layer
  /// instead of being obsoleted by it.
  static const double launderPerCoin = 0.00035;
  static const double launderCapPerSale = 0.6;

  static const int patrolCheckInterval = 12; // twice a game-day
  static const double patrolSlope = 0.0040;
  static const double patrolMaxChance = 0.22;

  /// Fixed, and nothing in the game may alter it in either direction.
  static const int inspectionWindowTicks = 24;

  /// What the Crown pays for contraband you hand over voluntarily.
  static const double declaredSaleMultiplier = 0.45;

  static const List<String> cutterNames = [
    'HMS Diligent', 'HMS Kestrel', 'HMS Tidewaiter',
    'HMS Sentinel', 'HMS Cormorant', 'HMS Reckoning',
  ];

  // ---- Rival raids ------------------------------------------------------
  /// Base value of contraband below which no raid is ever rolled.
  static const double raidHoardFloor = 3000.0;
  static const double raidHoardScale = 60000.0;
  static const double raidMaxChance = 0.10;
  static const double raidRepelPerCrew = 0.18;
  static const double raidRepelMax = 0.85;
  static const double raidPowderCost = 6.0;

  // ---- Prize-taking and Letters of Marque -------------------------------
  //
  // There are no prize VOYAGES. Boarding resolves in the tick you press it,
  // against a ship already sitting at your quay. The rule this enforces, which
  // governs the whole codebase: no player-owned object may carry a field whose
  // value improves as a function of elapsed ticks alone. No readyAt, no eta,
  // no progress bar. There is therefore no wait that money could ever shorten.

  static const double prizePowderCost = 8.0;
  static const double prizeBaseSuccess = 0.30;
  static const double prizeSuccessPerCrew = 0.11;
  static const double prizeCoveredBonus = 0.06;
  static const double prizeSuccessCap = 0.80;

  /// Cargo above the storage cap is bought off you at half price rather than
  /// destroyed — a full shed should never make a won fight feel like a loss.
  static const double prizeOverflowSaleMultiplier = 0.5;

  /// Relative weight of each cargo in a prize hold.
  static const Map<Resource, int> prizeTable = {
    Resource.ore: 22,
    Resource.timber: 18,
    Resource.flax: 16,
    Resource.planks: 14,
    Resource.grain: 8,
    Resource.tools: 8,
    Resource.sailcloth: 6,
    // The only source of spice in the game. Small, because a hull's worth is
    // not meant to solve a run — several prizes are a shortcut, one is a taste.
    Resource.spice: 6,
  };

  static const double heatPerUncoveredPrizeTon = 0.05;
  static const double heatPerFailedBoardingUncovered = 3.0;
  static const double heatPerFailedBoardingCovered = 1.0;

  /// Above this the Admiralty will not sell you coverage. Existing tonnage
  /// still spends down normally.
  static const double letterHeatCeiling = 45.0;

  // ---- The chandler and voyages -----------------------------------------

  /// The chandler's cut over the going rate. Dearer than an import berth,
  /// which is a rate you staff — this is the premium for having it now.
  static const double chandlerMarkup = 1.62;

  /// What the chandler will handle: raw stock and food only.
  ///
  /// Every finished good in the win condition still has to come out of a shed
  /// you built and staffed. Coin buys you inputs, never the answer.
  static const List<Resource> chandlerStock = [
    Resource.timber,
    Resource.flax,
    Resource.ore,
    Resource.grain,
    Resource.fish,
  ];

  /// How many consignments can be at sea at once.
  static const int maxVoyages = 3;

  /// Powder burnt to sail escorted, which halves the risk of being taken.
  static const double escortPowderCost = 10.0;

  static const int marqueCoinPerTon = 14;
  static const double marqueSailclothPerTon = 0.05;
  static const double marqueToolsPerTon = 0.02;
}

enum LogKind { info, good, warn, bad }

class LogEntry {
  LogEntry(this.tick, this.text, this.kind);
  final int tick;
  final String text;
  final LogKind kind;
}

class GameState {
  GameState._({
    required this.tick,
    required this.stock,
    required this.coin,
    required this.buildings,
    required this.population,
    required this.market,
    required this.rng,
    required this.lighthouseBuilt,
  });

  /// A fresh port: three extractors, two cottage rows, and enough coin to make
  /// one real decision on the first day.
  factory GameState.newGame({int seed = 20260815, CharterSet? charters}) {
    final ch = charters ?? CharterSet.none;
    final state = GameState._(
      tick: 0,
      // Deliberately small. Two sheds and five hands is one idea — put people
      // to work, cart in what they make — and everything else arrives later,
      // one building at a time, once you have earned it.
      stock: ResourceBag({
        Resource.timber: 25,
        Resource.grain: 18,
        Resource.fish: 18,
        Resource.planks: 10,
      }),
      coin: 300 + ch.startCoin,
      buildings: [
        Building(defId: 'forest_camp', workers: 2),
        Building(defId: 'fishing_wharf', workers: 2),
        Building(defId: 'house'),
      ],
      population: 5 + ch.startPopulation,
      market: Market(),
      rng: SeededRng(seed),
      lighthouseBuilt: false,
    );
    state.charters = ch;
    state.placeAll();
    state.syncYards();
    state.unlocked.addAll(kInitiallyUnlocked);
    state.log('The harbourmaster takes the post. Five souls, one tide.',
        LogKind.info);
    return state;
  }

  int tick;
  final ResourceBag stock;
  int coin;
  final List<Building> buildings;
  int population;
  final Market market;
  final SeededRng rng;
  bool lighthouseBuilt;

  /// A day-by-day trace of this run, for lining the balance bot up against
  /// real play. Recording only; nothing reads it during a game.
  RunJournal journal = RunJournal();

  /// What the dark trade has actually been worth, and what it has cost.
  ///
  /// Reported from play: "I skip it because it doesn't feel worth the
  /// investment... just adds another layer for no real payoff." Measured
  /// against the same eight seeds it is worth about twelve days of a hundred
  /// and twenty — real, but a tenth of a run is invisible without a control run
  /// to compare against, and nothing on screen ever said so. A layer whose
  /// payoff the player cannot see is one they are right to skip.
  ///
  /// Coin from selling contraband, and the market value of goods taken in
  /// barter, against the value of everything seized or raided.
  double darkEarned = 0;
  double darkLost = 0;

  /// Net worth of the dark trade so far, in coin.
  double get darkNet => darkEarned - darkLost;

  /// Whether this run's victory has already been written to the profile.
  ///
  /// Belongs to the run rather than to a widget. It used to be a `bool` field
  /// on the game screen's State, which nothing ever reset — so the second run
  /// you finished in one sitting was silently discarded: no record, no charter,
  /// no dialog. Living here it resets with the port and survives a reload,
  /// which is what "once per run" actually means.
  bool victoryRecorded = false;

  /// The weather and the wider world. Replaced wholesale on load.
  EventSystem events = EventSystem();

  /// Standing conditions carried in from previous runs.
  CharterSet charters = CharterSet.none;

  /// How closely the Crown is watching. 0 for an honest port, forever.
  double notoriety = 0.0;

  /// Tick the cutter on station will board, or -1 for no cutter.
  int cutterInspectTick = -1;

  double contrabandSeized = 0.0;

  /// How far word has spread toward the next arrival, 0..1.
  double growthProgress = 0;

  /// Someone moved in on this tick. Transient — the UI reads it to show a
  /// flash, and it is cleared at the start of the next step.
  int arrivalsThisTick = 0;

  /// Consignments currently at sea.
  final List<Voyage> voyages = [];

  /// Building ids the port has learned to raise. Sticky once earned.
  final Set<String> unlocked = {};

  /// Highest level hired on each track, 0 for nobody.
  int captainLevel = 0;
  int merchantLevel = 0;
  int quartermasterLevel = 0;

  // ---- The dark trade, all derived so a save can never disagree ----------

  /// Building any dark shed opens the free-trader market. A port with none of
  /// them never sees a cutter, because there is nothing for one to find.
  bool get darkTradeOpen =>
      buildings.any((b) => kDarkBuildingIds.contains(b.defId));

  double get contrabandUnits =>
      Resource.contraband.fold(0.0, (s, r) => s + stock[r]);

  /// Concealment is bought with hands, not coin — so it is bounded by housing
  /// and every unit you hide is a worker not in a shed.
  double get concealCapacity => buildings.fold(
      0.0, (s, b) => s + b.workers * b.def.concealPerWorker);

  double get exposedUnits =>
      (contrabandUnits - concealCapacity).clamp(0.0, double.infinity);

  /// How much of resource [r] is sitting in plain sight.
  double exposedShareOf(Resource r) {
    final total = contrabandUnits;
    if (total <= 0) return 0;
    return stock[r] / total * exposedUnits;
  }

  double get contrabandBaseValue =>
      Resource.contraband.fold(0.0, (s, r) => s + stock[r] * r.basePrice);

  int get berthCrew => buildings
      .where((b) => b.defId == 'privateer_berth')
      .fold(0, (s, b) => s + b.workers);

  String get noticeBand {
    if (notoriety <= Balance.patrolFloor) return 'Unremarked';
    if (notoriety < 30) return 'Noticed';
    if (notoriety < 45) return 'Watched';
    return 'Marked';
  }

  bool get cutterOnStation => cutterInspectTick >= 0;

  String cutterName() => Balance.cutterNames[
      (tick ~/ Balance.ticksPerDay) % Balance.cutterNames.length];

  final List<LogEntry> logEntries = [];

  // ---- Derived state ----------------------------------------------------

  int get day => tick ~/ Balance.ticksPerDay + 1;
  int get hour => tick % Balance.ticksPerDay;

  int get assignedWorkers =>
      buildings.fold(0, (sum, b) => sum + b.workers);
  int get idleWorkers => population - assignedWorkers;

  int get housingCapacity =>
      Balance.baseHousing + buildings.fold(0, (s, b) => s + b.def.housing);

  int get cottageCount => buildings.where((b) => b.def.housing > 0).length;

  /// The housing sum spelled out, so a player who thinks the count is off by
  /// one can see exactly where every roof comes from.
  String get housingBreakdown {
    final built = housingCapacity - Balance.baseHousing;
    return "the harbourmaster's house (${Balance.baseHousing}) + "
        '$cottageCount ${cottageCount == 1 ? "cottage" : "cottages"} '
        '($built) = $housingCapacity';
  }

  double get storageCapacity =>
      (Balance.baseStorage + buildings.fold(0.0, (s, b) => s + b.def.storage)) *
      charters.storage;

  /// Warehouses do two jobs: they raise the stores, and they give every shed a
  /// bigger yard. "My sheds keep filling up" should have an answer you can go
  /// and build.
  double get yardMultiplier =>
      1 + Balance.yardBonusPerWarehouse * buildings.where((b) => b.def.storage > 0).length;

  /// Push the current warehouse bonus onto every shed. Cheap, and keeps the UI
  /// honest before the first tick has run.
  void syncYards() {
    final m = yardMultiplier;
    for (final b in buildings) {
      b.yardBonus = m;
    }
  }

  double get foodStock => Resource.values
      .where((r) => r.isFood)
      .fold(0.0, (s, r) => s + stock[r]);

  /// Days of food remaining at the current headcount.
  double get foodDays => population == 0
      ? double.infinity
      : foodStock / (population * Balance.foodPerPersonPerDay);

  int get dailyWageBill => assignedWorkers * Balance.wagePerWorkerPerDay;

  /// Why the town is not growing, or null if it is.
  ///
  /// Growth quietly needs a food buffer as well as a spare roof, which made a
  /// port sitting one under its housing look like an off-by-one in the
  /// cottage. If something is holding the town back, say which thing.
  String? get growthBlocker {
    if (population >= housingCapacity) {
      return 'Every roof is taken — build a cottage to grow further';
    }
    // Checked before food because it is the one that actively costs you
    // people: an unpaid crew leaves, which cancels out the growth roll and
    // leaves the town apparently stuck for no visible reason.
    if (coin < dailyWageBill + retinueWageBill) {
      return 'The payroll is short — unpaid hands leave, and the town cannot '
          'grow while it is losing people';
    }
    if (foodDays < Balance.growthFoodDays) {
      return 'Not enough food put by — the town wants '
          '${Balance.growthFoodDays.toStringAsFixed(0)} days in store '
          'before anyone new moves in';
    }
    return null;
  }

  /// Days of wages the treasury can still cover.
  double get wageRunwayDays {
    final bill = dailyWageBill + retinueWageBill;
    return bill <= 0 ? double.infinity : coin / bill;
  }

  /// True when the purse is running down and nothing has been sold to refill
  /// it. Surfaced before the money is gone, not after.
  bool get payrollAtRisk => wageRunwayDays < 4;

  /// True when the blocker is something gone wrong rather than simply a full
  /// town, so the HUD only shouts when there is something to fix.
  bool get growthIsStalled =>
      population < housingCapacity && growthBlocker != null;

  /// What the town is doing about its numbers, always — not just when
  /// something is wrong.
  ///
  /// Growth is a coin flip each day, so a working port gains someone roughly
  /// every other day with nothing on screen to say so. Silence reads exactly
  /// like being stuck, which is worse than being stuck.
  String get growthStatus {
    final blocked = growthBlocker;
    if (blocked != null) return blocked;
    final room = housingCapacity - population;
    final due = daysToNextArrival;
    final when = due <= 1.0
        ? 'someone arrives tomorrow'
        : 'next hand in about ${due.ceil()} days';
    return 'The town is growing — $when, '
        '$room ${room == 1 ? "roof" : "roofs"} still free';
  }

  bool get isGrowing => growthBlocker == null;

  /// Days until the next hand turns up, if nothing changes.
  double get daysToNextArrival {
    final rate = Balance.growthChance * charters.growth;
    if (rate <= 0) return double.infinity;
    return (1.0 - growthProgress) / rate;
  }

  int get lighthouseCoinCost =>
      (Balance.lighthouseCoin * charters.lighthouseCost).round();

  Map<Resource, double> get lighthouseGoodsCost => Balance.lighthouseCost
      .map((r, q) => MapEntry(r, q * charters.lighthouseCost));

  bool get canBuildLighthouse =>
      !lighthouseBuilt &&
      coin >= lighthouseCoinCost &&
      stock.canAfford(lighthouseGoodsCost);

  void log(String text, LogKind kind) {
    logEntries.insert(0, LogEntry(tick, text, kind));
    if (logEntries.length > 40) logEntries.removeLast();
  }

  // ---- Simulation -------------------------------------------------------

  /// Advance one game-hour.
  ///
  /// [interactive] is false only during offline catch-up. Enforcement — the
  /// cutter, the seizure, the rival raid — is the one thing that never runs
  /// while the app is closed. Everything else does.
  void step({bool interactive = true}) {
    tick++;
    arrivalsThisTick = 0;
    _applyEventTransitions(events.advance(tick,
        pressure: _eventContext().pressure * charters.hazardSeverity));
    _landImports();
    _produce();
    _crewBerths();
    _accrueHeat();
    _settleVoyages();
    if (interactive) _revenue();
    final dayTurned = tick % Balance.ticksPerDay == 0;
    if (dayTurned) {
      _endOfDay(interactive: interactive);
      checkUnlocks();
      _rollEvent();
    }
    _runAutoCollect(dayTurned: dayTurned);
    market.advance(tick, rng, events.effects.conditions, darkTradeOpen,
        notoriety);
  }

  /// A standing crew eats stores whether or not it sails.
  ///
  /// Throttles like every other building rather than failing binary, so a berth
  /// short of rope runs slow instead of dropping into a silent dead state.
  void _crewBerths() {
    for (final b in buildings) {
      final def = b.def;
      if (!def.isCrewed || b.workers == 0) continue;

      double readiness = 1.0;
      def.upkeep.forEach((r, perWorker) {
        final need = perWorker * b.workers;
        if (need > 0) {
          readiness = readiness.clamp(0.0, (stock[r] / need).clamp(0.0, 1.0));
        }
      });
      def.upkeep
          .forEach((r, pw) => stock.remove(r, pw * b.workers * readiness));
      b.lastEfficiency = readiness;
    }
  }

  /// Only contraband sitting in plain sight is conspicuous. Concealed stock
  /// contributes exactly nothing, so the meter never fills while you do
  /// nothing wrong — and there is no decay, because there is nothing to wait
  /// out. Notoriety is a ledger you work off, not a timer you sit through.
  void _accrueHeat() {
    if (contrabandUnits <= 0) return;
    var load = 0.0;
    for (final r in Resource.contraband) {
      load += exposedShareOf(r) * r.heatWeight;
    }
    if (load <= 0) return;
    _addHeat(load * Balance.heatPerExposedUnitPerTick);
  }

  void _addHeat(double delta) {
    notoriety = (notoriety + delta).clamp(0.0, 100.0);
  }

  void _revenue() {
    if (notoriety <= Balance.patrolFloor) {
      if (cutterOnStation) {
        cutterInspectTick = -1;
        log('The cutter stood off without boarding.', LogKind.good);
      }
      return; // before any rng draw at all
    }
    if (cutterOnStation) {
      if (tick >= cutterInspectTick) _resolveInspection();
      return;
    }
    if (tick % Balance.patrolCheckInterval != 0) return;

    final p = ((notoriety - Balance.patrolFloor) * Balance.patrolSlope)
        .clamp(0.0, Balance.patrolMaxChance);
    if (rng.next() >= p) return;

    cutterInspectTick = tick + Balance.inspectionWindowTicks;
    log('${cutterName()} put into the quay. She boards in '
        '${Balance.inspectionWindowTicks} hours.', LogKind.warn);
  }

  /// Draws no randomness whatsoever. The outcome is a pure function of state
  /// the player has been staring at all along — which is what makes a seizure
  /// feel like a decision you already made rather than a slot machine firing.
  void _resolveInspection() {
    cutterInspectTick = -1;

    if (exposedUnits <= 1e-6) {
      _addHeat(Balance.heatCleanInspection);
      log('They found nothing but salt fish. A tidy quay is its own defence.',
          LogKind.good);
      return;
    }

    var total = 0.0;
    for (final r in Resource.contraband) {
      final taken = exposedShareOf(r);
      if (taken <= 0) continue;
      darkLost += taken * market.priceOf(r);
      stock.remove(r, taken);
      total += taken;
    }
    contrabandSeized += total;
    _addHeat(Balance.heatPerSeizure);
    // The Crown takes the cargo. No coin fine, and no legitimate good is ever
    // touched — not a plank, not a tool, not a loaf, not a single hand.
    log('The Revenue took ${total.round()} units off the quay.', LogKind.bad);
  }

  /// Rivals know exactly where you would hide it, so concealment is no defence
  /// at all against your own trade. That is the pressure that forces turnover.
  void _rivalRaid() {
    final value = contrabandBaseValue;
    if (value <= Balance.raidHoardFloor) return;

    final p = ((value - Balance.raidHoardFloor) / Balance.raidHoardScale)
        .clamp(0.0, Balance.raidMaxChance);
    if (rng.next() >= p) return;

    var repel = (Balance.raidRepelPerCrew * berthCrew)
        .clamp(0.0, Balance.raidRepelMax);
    final armed = stock[Resource.powder] >= Balance.raidPowderCost;
    if (!armed) repel *= 0.5;

    if (berthCrew > 0 && rng.next() < repel) {
      if (armed) stock.remove(Resource.powder, Balance.raidPowderCost);
      log('Rivals came for the hoard and were beaten off the mole.',
          LogKind.good);
      return;
    }

    final frac = rng.range(0.20, 0.40);
    var taken = 0.0;
    for (final r in Resource.contraband) {
      final loss = stock[r] * frac;
      darkLost += loss * market.priceOf(r);
      stock.remove(r, loss);
      taken += loss;
    }
    if (taken > 0) {
      log('Rivals took ${taken.round()} units out of the cellars in the night.',
          LogKind.bad);
    }
  }

  /// One-off effects fire the instant an event lands, and the log narrates
  /// both ends of it.
  void _applyEventTransitions(EventTransitions t) {
    for (final e in t.started) {
      final d = e.def;
      final p = events.pressure;
      d.onsetStockScale.forEach((r, mul) {
        // A quarter of the sheds burning is a scratch on a big port; scale the
        // loss, floored so it can never wipe you out.
        final scaled = (1.0 - (1.0 - mul) * p).clamp(0.35, 1.0);
        stock[r] = stock[r] * scaled;
      });
      d.onsetStockGrant.forEach((r, qty) {
        final room = (storageCapacity - stock[r]).clamp(0.0, double.infinity);
        stock.add(r, qty < room ? qty : room);
      });
      if (d.onsetCoinScale != 1.0) coin = (coin * d.onsetCoinScale).round();

      var line = d.onsetLine;
      if (d.targetsAGood && e.target != null) {
        line = '$line (${e.target!.label})';
      }
      log('${d.icon} $line',
          d.severity == EventSeverity.boon ? LogKind.good : LogKind.bad);
    }
    for (final e in t.ended) {
      log('${e.def.icon} ${e.def.liftLine}', LogKind.info);
    }
  }

  void _rollEvent() {
    final ev = events.rollAtDayEnd(tick, rng, _eventContext());
    if (ev == null) return;
    final d = ev.def;
    log('${d.icon} ${d.omenLine}',
        d.severity == EventSeverity.boon ? LogKind.good : LogKind.warn);
  }

  EventContext _eventContext() => EventContext(
        day: day,
        buildableCount: buildings.where((b) => b.def.buildable).length,
        population: population,
        assignedWorkers: assignedWorkers,
        foodDays: foodDays,
        coin: coin,
        dailyWageBill: dailyWageBill,
        buildingIds: buildings.map((b) => b.defId).toSet(),
        producingSheds: producingSheds,
        hazardGap: charters.hazardGap,
      );

  /// Spend coin to land raw cargo.
  ///
  /// TWO RULES THAT MUST NOT BE BROKEN:
  ///   1. NEVER present imports as purchasable quantities or crates. This is a
  ///      RATE you staff, not a basket you check out. A rate cannot be repriced
  ///      as a package without rebuilding the feature — which is precisely what
  ///      makes the shop shape impossible to slide in later.
  ///   2. NEVER add a delay between paying and receiving. Coin becomes cargo in
  ///      the same tick. A speed-up cannot be sold against a duration that does
  ///      not exist.
  ///
  /// Runs as its own phase before [_produce] rather than as a branch inside it:
  /// otherwise whether a berth landing timber to the cap starves a forest camp
  /// would depend on where the player happened to build each one.
  void _landImports() {
    final cap = storageCapacity;
    final cushion = dailyWageBill * Balance.importWageCushionDays;

    for (final b in buildings) {
      if (!b.def.imports) continue;
      if (b.workers == 0) {
        b.lastEfficiency = 0.0;
        continue;
      }

      final r = b.importResource;
      final unit = market.priceOf(r) * Balance.importMargin;
      final budget = Balance.importCoinPerWorkerTick * b.workers;
      final purse = (coin - cushion).clamp(0.0, double.infinity);
      final room = (cap - stock[r]).clamp(0.0, double.infinity);

      // Floor the spend to whole coin and derive the landed units FROM the
      // floored figure, never the reverse — that keeps an int treasury exact
      // with no fractional carry to serialise.
      final spend = [budget, purse, room * unit]
          .reduce((a, c) => a < c ? a : c)
          .floorToDouble();

      b.lastEfficiency = budget <= 0 ? 0.0 : (spend / budget).clamp(0.0, 1.0);
      if (spend < 1 || unit <= 0) continue;

      final landed = spend / unit;
      coin -= spend.toInt();
      stock.add(r, landed);
      // Leaning on one cargo walks its index up and shrinks what the same coin
      // buys, while the drain stays flat. Spreading across the three is
      // strictly better — the same lesson selling already teaches.
      market.applyPurchasePressure(r, landed);
    }
  }

  void _produce() {
    syncYards();
    final absence = _deriveAbsence();

    for (final b in buildings) {
      final def = b.def;
      if (def.imports) continue; // already handled in _landImports

      b.eventThrottle = events.effects.throughputFor(def.id);
      final absent = absence[b] ?? 0;
      final hands = (b.workers - absent).clamp(0, b.workers);

      // An event that slows a shed is just fewer effective hands. Folding the
      // throttle into the worker count as a double means the whole existing
      // scarcest-constraint loop below applies with no other change.
      final effWorkers = hands * b.eventThrottle;
      final yieldMul = events.effects.yieldFor(def.id);

      if (def.outputs.isEmpty || effWorkers <= 1e-9) {
        // lastEfficiency must keep meaning "starved of input" and nothing
        // else, or the UI warning becomes a lie during every gale. A shed
        // stopped by weather is not starved — it is simply shut.
        b.lastEfficiency = b.workers > 0 ? 1.0 : 0.0;
        continue;
      }

      double efficiency = 1.0;

      def.inputs.forEach((r, perWorker) {
        final need = perWorker * effWorkers;
        if (need > 0) {
          efficiency = efficiency.clamp(0.0, (stock[r] / need).clamp(0.0, 1.0));
        }
      });

      def.outputs.forEach((r, perWorker) {
        final made = perWorker * effWorkers * yieldMul;
        if (made > 0) {
          // A full yard stalls the shed exactly like a dry input does.
          final room =
              (b.holdCapOf(r) - (b.hold[r] ?? 0)).clamp(0.0, double.infinity);
          efficiency = efficiency.clamp(0.0, (room / made).clamp(0.0, 1.0));
        }
      });

      if (efficiency > 0) {
        // Inputs are consumed in full; only the output carries yieldMul. That
        // difference is what spoiled flax and a fouled saw blade actually are.
        def.inputs
            .forEach((r, pw) => stock.remove(r, pw * effWorkers * efficiency));
        def.outputs.forEach((r, pw) => b.hold[r] = (b.hold[r] ?? 0) +
            pw * effWorkers * efficiency * yieldMul * charters.production);
      }
      b.lastEfficiency = efficiency;
    }
  }

  /// Spread the day's absent hands over the largest crews first — the same
  /// rule [_clampAssignments] uses.
  ///
  /// Derived fresh every tick from the CURRENT assignment and never written
  /// into [Building.workers]. That closes the reshuffle exploit (you cannot
  /// dodge a fever by moving hands between sheds) and guarantees the port
  /// snaps back to exactly the allocation you built when it lifts.
  Map<Building, int> _deriveAbsence() {
    var left = events.effects.absentTotal;
    if (left <= 0) return const {};

    final out = <Building, int>{};
    while (left > 0) {
      Building? best;
      var bestRemaining = 0;
      for (final b in buildings) {
        final remaining = b.workers - (out[b] ?? 0);
        if (remaining > bestRemaining) {
          bestRemaining = remaining;
          best = b;
        }
      }
      if (best == null) break; // fewer assigned hands than absent
      out[best] = (out[best] ?? 0) + 1;
      left--;
    }
    return out;
  }

  void _endOfDay({bool interactive = true}) {
    _feedTown();
    _payWages();
    _growTown();
    if (interactive) _rivalRaid();
    _recordDay(interactive: interactive);
  }

  void _recordDay({bool interactive = true}) {
    // A run is over when the light is lit. Everything after it is a port
    // nobody is steering, and it does not belong in a trace of how the run
    // was played.
    //
    // This cost a real report. A save from before the journal existed was
    // reopened in a later build, left running, and sent: 89 rows of
    // population 0, coin 0, no milestones, 27 buildings still standing — a
    // port whose people had starved and whose coin had gone to wages, which
    // reads as a catastrophic collapse rather than as the win it followed.
    // Left alone it would also have evicted the real days at the 400-day cap.
    if (lighthouseBuilt) return;

    // Days simulated while the app was closed are real days, but nobody made
    // a decision on them. Counting them separately is the difference between
    // "a player took 120 days" and "a player played 70 days and left it
    // running for 50" — which are not the same reading at all, and the bot
    // plays every day actively.
    if (!interactive) journal.unattendedDays += 1;

    journal.record(JournalDay(
      day: day,
      population: population,
      coin: coin,
      buildings: buildings.length,
      staffed: staffedSheds,
      foodDays: foodDays.isFinite ? foodDays : 0,
      atSea: voyages.length,
    ));
  }

  void _feedTown() {
    var needed = population *
        Balance.foodPerPersonPerDay *
        events.effects.foodScale *
        charters.foodUse;

    // Fish spoils, grain keeps — so the town eats the sea first.
    for (final r in [Resource.fish, Resource.grain]) {
      if (needed <= 0) break;
      final taken = stock[r] < needed ? stock[r] : needed;
      stock.remove(r, taken);
      needed -= taken;
    }

    if (needed > 1e-6 && population > 0) {
      population -= 1;
      _clampAssignments();
      log('Stores ran dry. A family left on the evening tide.', LogKind.bad);
    }
  }

  void _payWages() {
    final bill =
        (dailyWageBill * events.effects.wageScale).round() + retinueWageBill;
    if (coin >= bill) {
      coin -= bill;
      return;
    }

    coin = 0;
    // An unpaid crew is a spiral: fewer hands means less output, which means
    // less coin, which means more unpaid wages. Left unfloored it walks a port
    // all the way down with no way back. Losses are rarer than they were and
    // stop at a skeleton crew, so a bad stretch is recoverable by selling your
    // way out rather than terminal.
    if (population > Balance.wageLossFloor &&
        rng.next() < Balance.wageLossChance) {
      population -= 1;
      _clampAssignments();
      log('Wages went unpaid. A worker signed onto another crew.', LogKind.bad);
    } else {
      log('Wages went unpaid. The docks are grumbling.', LogKind.warn);
    }
  }

  /// Word gets round at a steady rate rather than on a coin flip.
  ///
  /// A 50% daily roll averages one arrival every two days but produces long
  /// dead stretches — reported from play as a town sitting at the same number
  /// for eleven days. Accumulating progress gives the same average with none
  /// of the streaks, and it can be shown as a bar, which a dice roll never
  /// could. Conditions pause it rather than resetting it, so a hungry week
  /// costs you time and not the progress you had already made.
  void _growTown() {
    if (population >= housingCapacity) {
      growthProgress = 0;
      return;
    }
    // Growth needs a genuine buffer, not just a day scraped through.
    if (foodDays < Balance.growthFoodDays) return;
    if (coin <= 0) return; // an unpaid port attracts nobody

    growthProgress += Balance.growthChance * charters.growth;
    if (growthProgress >= 1.0) {
      growthProgress -= 1.0;
      population += 1;
      arrivalsThisTick += 1;
      log('A new hand arrived looking for work.', LogKind.good);
    }
  }

  /// Workers cannot outnumber the population; trim from the largest crews
  /// first so a death does not silently empty a whole workshop.
  void _clampAssignments() {
    while (assignedWorkers > population) {
      final busiest = buildings
          .where((b) => b.workers > 0)
          .fold<Building?>(null, (best, b) =>
              best == null || b.workers > best.workers ? b : best);
      if (busiest == null) break;
      busiest.workers -= 1;
    }
  }

  /// Run the sim forward for time spent with the app closed.
  ///
  /// Deliberately uncapped in *progress*: no timer to skip, nothing to buy to
  /// speed it up. Production while away is bounded only by the storage you
  /// built, since nothing sells itself. [Balance.maxCatchUpTicks] bounds the
  /// compute, and by then every store is long since full anyway.
  int catchUp(Duration elapsed, {required double ticksPerSecond}) {
    final wanted = (elapsed.inMilliseconds / 1000.0 * ticksPerSecond).floor();
    final ticks = wanted.clamp(0, Balance.maxCatchUpTicks);
    for (var i = 0; i < ticks; i++) {
      step(interactive: false);
    }
    if (ticks > 0) {
      log('While you were away: $ticks hours passed in the port.', LogKind.info);
    }

    // Nothing was taken while the app was closed. If the port is conspicuous,
    // a cutter is placed now — deterministically, drawing no randomness — so
    // you come back to a live decision with a full window, never to a loss
    // that already happened. Putting the phone down must never be a punished
    // action; that is the hook this whole project exists to reject.
    if (ticks > 0 &&
        notoriety > Balance.patrolFloor &&
        exposedUnits > 1e-6 &&
        !cutterOnStation) {
      cutterInspectTick = tick + Balance.inspectionWindowTicks;
      log('A revenue cutter stood in while you were away. '
          'She boards at first light.', LogKind.warn);
    }
    return ticks;
  }

  // ---- Player actions ---------------------------------------------------

  // ---- Working a whole trade at once -------------------------------------
  //
  // Once a port has five forest camps, assigning them one card at a time is
  // the same tedium as collecting them one at a time. These operate on a
  // trade rather than a building.

  List<Building> shedsOfType(String defId) =>
      buildings.where((b) => b.defId == defId).toList();

  /// Every staffable trade in the port, in catalogue order so the list does
  /// not reshuffle as you build.
  List<String> get staffableTypes {
    final seen = <String>{};
    final out = <String>[];
    for (final d in kBuildingDefs) {
      if (!d.isStaffable) continue;
      if (buildings.any((b) => b.defId == d.id) && seen.add(d.id)) {
        out.add(d.id);
      }
    }
    return out;
  }

  /// Put one idle hand on this trade, filling the emptiest shed first so the
  /// group stays evenly worked.
  bool addWorkerTo(String defId) {
    if (idleWorkers <= 0) return false;
    Building? target;
    for (final b in shedsOfType(defId)) {
      if (b.workers >= b.def.maxWorkers) continue;
      if (target == null || b.workers < target.workers) target = b;
    }
    if (target == null) return false;
    target.workers += 1;
    return true;
  }

  /// Take one hand off this trade, from the fullest shed.
  bool removeWorkerFrom(String defId) {
    Building? target;
    for (final b in shedsOfType(defId)) {
      if (b.workers <= 0) continue;
      if (target == null || b.workers > target.workers) target = b;
    }
    if (target == null) return false;
    target.workers -= 1;
    return true;
  }

  bool setWorkers(int buildingIndex, int count) {
    final b = buildings[buildingIndex];
    final clamped = count.clamp(0, b.def.maxWorkers);
    final delta = clamped - b.workers;
    if (delta > 0 && delta > idleWorkers) return false;
    b.workers = clamped;
    return true;
  }

  // ---- The map ----------------------------------------------------------

  /// The building occupying this tile, if any.
  Building? buildingAt(int col, int row) {
    for (final b in buildings) {
      if (!b.isPlaced) continue;
      final f = b.def.footprint;
      if (col >= b.col && col < b.col + f && row >= b.row && row < b.row + f) {
        return b;
      }
    }
    return null;
  }

  /// Can [def] stand with its top-left corner here? Every tile of the footprint
  /// must be buildable ground and free of other buildings.
  bool canPlaceAt(BuildingDef def, int col, int row, {Building? ignore}) {
    final f = def.footprint;
    for (var c = col; c < col + f; c++) {
      for (var r = row; r < row + f; r++) {
        if (c < 0 || r < 0 || c >= Terrain.size || r >= Terrain.size) {
          return false;
        }
        if (!Terrain.buildableAt(c, r)) return false;
        final occupant = buildingAt(c, r);
        if (occupant != null && !identical(occupant, ignore)) return false;
      }
    }
    return true;
  }

  /// Pick a building up and set it down somewhere else. Returns false — and
  /// changes nothing — if it will not fit.
  bool moveBuilding(Building b, int col, int row) {
    if (!canPlaceAt(b.def, col, row, ignore: b)) return false;
    b.col = col;
    b.row = row;
    return true;
  }

  /// First free spot, spiralling out from the middle of the island, so a new
  /// shed lands somewhere sensible without the player having to place it.
  bool autoPlace(Building b) {
    const centre = Terrain.size ~/ 2;
    for (var ring = 0; ring < Terrain.size; ring++) {
      for (var dc = -ring; dc <= ring; dc++) {
        for (var dr = -ring; dr <= ring; dr++) {
          // Only the perimeter of each ring is new.
          if (ring > 0 && dc.abs() != ring && dr.abs() != ring) continue;
          final c = centre + dc;
          final r = centre + dr;
          if (canPlaceAt(b.def, c, r, ignore: b)) {
            b.col = c;
            b.row = r;
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Give every unplaced building a home. Runs on load, so a save written
  /// before the map existed lays itself out rather than arriving empty.
  void placeAll() {
    for (final b in buildings) {
      if (!b.isPlaced) autoPlace(b);
    }
  }

  /// Cart a shed's yard into the stores. Returns what was actually taken.
  ///
  /// Bounded by the storage you built, which stays the only real limiter: what
  /// will not fit simply stays in the yard.
  Map<Resource, double> collect(Building b) {
    final taken = <Resource, double>{};
    final cap = storageCapacity;
    for (final r in b.hold.keys.toList()) {
      final held = b.hold[r] ?? 0;
      if (held <= 0) continue;
      final room = (cap - stock[r]).clamp(0.0, double.infinity);
      final moved = held < room ? held : room;
      if (moved <= 0) continue;
      stock.add(r, moved);
      b.hold[r] = held - moved;
      taken[r] = moved;
    }
    b.hold.removeWhere((_, v) => v <= 1e-9);
    checkUnlocks(); // carting in the first 40 timber should say so at once
    return taken;
  }

  /// Every yard at once. The whole port is never more than one tap away.
  Map<Resource, double> collectAll() {
    final total = <Resource, double>{};
    for (final b in buildings) {
      collect(b).forEach((r, v) => total[r] = (total[r] ?? 0) + v);
    }
    return total;
  }

  /// True when anything anywhere is waiting to be carted in.
  bool get hasAnythingToCollect =>
      buildings.any((b) => b.hasCollectableOutput);

  double get pendingCollection =>
      buildings.fold(0.0, (s, b) => s + b.holdTotal);

  // ---- The chandler ------------------------------------------------------

  double chandlerPrice(Resource r) =>
      market.priceOf(r) * Balance.chandlerMarkup;

  /// The most of [r] you could take right now, bounded by coin and shed room.
  double chandlerMax(Resource r) {
    final unit = chandlerPrice(r);
    if (unit <= 0) return 0;
    final affordable = coin / unit;
    final room = (storageCapacity - stock[r]).clamp(0.0, double.infinity);
    return affordable < room ? affordable : room;
  }

  /// Buy from the chandler, on demand, at a premium. Returns coin spent.
  double buyFromChandler(Resource r, double qty) {
    if (!Balance.chandlerStock.contains(r)) return 0;
    final most = chandlerMax(r);
    final amount = qty < most ? qty : most;
    if (amount < 1) return 0;

    final cost = amount * chandlerPrice(r);
    coin -= cost.round();
    if (coin < 0) coin = 0;
    stock.add(r, amount);
    market.applyPurchasePressure(r, amount);
    log('Bought ${amount.round()} ${r.label.toLowerCase()} from the chandler '
        'for ${cost.round()}c.', LogKind.info);
    return cost;
  }

  // ---- Voyages -----------------------------------------------------------

  bool get canSendVoyage => voyages.length < Balance.maxVoyages;

  /// What a factor at [dest] will pay for this manifest, after the charter.
  int quoteVoyage(Destination dest, Map<Resource, double> cargo) =>
      quoteBreakdown(dest, cargo).net;

  /// The same quote, itemised, so the panel can show who moved the number.
  ///
  /// Built here rather than reassembled in the UI: a breakdown that recomputes
  /// the arithmetic separately is a breakdown that will eventually disagree
  /// with the figure beside it.
  VoyageQuote quoteBreakdown(Destination dest, Map<Resource, double> cargo) {
    var gross = 0.0;
    var units = 0.0;
    cargo.forEach((r, qty) {
      gross += qty * r.basePrice * dest.payFor(r);
      units += qty;
    });

    final afterMerchant = gross * voyagePayBonus * charters.salePrice;
    final commission = afterMerchant * voyageCommission;
    final fee = units * dest.charterPerUnit;
    // The retinue is paid out of the proceeds, before the charter is settled,
    // so the quote you are shown is what actually reaches your strongbox.
    final net = afterMerchant - commission - fee;

    return VoyageQuote(
      gross: gross,
      merchantBonus: afterMerchant - gross,
      commission: commission,
      charterFee: fee,
      net: net < 0 ? 0 : net.round(),
    );
  }

  /// How long a crossing to [dest] would take if sent now, itemised.
  ///
  /// The one place a crossing's length is worked out. sendVoyage uses it too,
  /// so a panel can never quote a crossing the hull does not sail.
  VoyageDays daysBreakdown(Destination dest) {
    final exact = dest.days *
        voyageSpeedFactor *
        charters.voyageDays *
        Balance.ticksPerDay;
    return VoyageDays(
      base: dest.days,
      captainFactor: voyageSpeedFactor,
      charterFactor: charters.voyageDays,
      ticks: exact.round().clamp(1, dest.days * 3 * Balance.ticksPerDay),
      ticksPerDay: Balance.ticksPerDay,
    );
  }

  /// Load cargo and send it. Returns false — changing nothing — if the hold
  /// cannot be filled from the stores.
  bool sendVoyage(Destination dest, Map<Resource, double> cargo,
      {bool escorted = false}) {
    if (!canSendVoyage) return false;

    // Clamp to what is actually in the stores rather than refusing outright.
    // A workshop can eat part of the cargo between loading the hold and
    // pressing send — a ropewalk chewing through the flax you just loaded is
    // the obvious case — and silently rejecting the whole consignment looks
    // exactly like the button doing nothing at all.
    final clean = <Resource, double>{};
    cargo.forEach((r, q) {
      if (q <= 0) return;
      final have = stock[r];
      final take = q < have ? q : have;
      if (take >= 1) clean[r] = take;
    });
    if (clean.isEmpty) return false;
    if (escorted && stock[Resource.powder] < Balance.escortPowderCost) {
      return false;
    }

    clean.forEach((r, q) => stock.remove(r, q));
    if (escorted) stock.remove(Resource.powder, Balance.escortPowderCost);

    final quote = quoteVoyage(dest, clean);
    // Fixed here and never touched again: hiring a faster captain tomorrow
    // does not reel in a hull that sailed today.
    final crossing = daysBreakdown(dest);
    voyages.add(Voyage(
      destinationId: dest.id,
      cargo: clean,
      departTick: tick,
      returnTick: tick + crossing.ticks,
      quotedCoin: quote,
      escorted: escorted,
      // Frozen with the quote and the days: a crossing sails under the terms
      // it left on, and cannot be improved by hiring after it has gone.
      riskFactor: voyageRiskFactor,
    ));

    // Selling abroad never touches your own quay, which is the whole point:
    // it is how you move volume without collapsing the local price.
    final units = clean.values.fold(0.0, (s, v) => s + v).round();
    journal.mark(
        day,
        'sent $units units to ${dest.name}, '
        '${crossing.label}, quoted ${quote}c',
        code: RunCode.voyageMark(
            day, units, dest.name, crossing.days, quote.round()));
    log('Sent $units units to ${dest.name}. Due back in ${crossing.label}, '
        'quoted ${quote}c.', LogKind.good);
    return true;
  }

  void _settleVoyages() {
    for (final v in List.of(voyages)) {
      if (tick < v.returnTick) continue;
      voyages.remove(v);

      final dest = v.destination;
      var risk = dest.risk * v.riskFactor;
      // Privateers in the lanes are exactly when a lone hull goes missing.
      // Read live and taken from the event's own field rather than a hard-coded
      // id, so the banner can state it and the two can never disagree.
      risk *= events.effects.voyageRiskScale;
      if (v.escorted) risk *= 0.5;

      if (rng.next() < risk) {
        log('The ${dest.name} consignment never made port. Taken, they say.',
            LogKind.bad);
        continue;
      }

      coin += v.quotedCoin;
      log('The ${dest.name} consignment paid out ${v.quotedCoin}c.',
          LogKind.good);
    }
  }

  // ---- The retinue -------------------------------------------------------

  int levelOn(RetinueTrack t) => switch (t) {
        RetinueTrack.captain => captainLevel,
        RetinueTrack.merchant => merchantLevel,
        RetinueTrack.quartermaster => quartermasterLevel,
      };

  Retainer? hiredOn(RetinueTrack t) => retainerAt(t, levelOn(t));

  /// The next person you could take on, or null at the top of the track.
  Retainer? nextOn(RetinueTrack t) => retainerAt(t, levelOn(t) + 1);

  /// Sheds with a **yard to cart** — what the quartermaster is measured
  /// against.
  ///
  /// The Import Berth is deliberately absent: it lands cargo straight into the
  /// stores rather than filling a yard, so there is nothing there for a
  /// quartermaster to collect. That is why this count and [staffedSheds]
  /// differ, and the difference is meant.
  int get producingSheds =>
      buildings.where((b) => b.def.outputs.isNotEmpty).length;

  /// Working sheds with somebody in them.
  ///
  /// The berth cap keys off this rather than off [producingSheds] for two
  /// separate reasons, and both are load-bearing.
  ///
  /// It must be *staffed*, because an empty shed costs nothing to keep: a
  /// player could throw up cheap huts they never worked and buy all three
  /// berths outright for a few hundred coin, which is precisely the pacing gate
  /// the cap exists to be.
  ///
  /// And it must count the Import Berth, which was reported from play as not
  /// counting toward officers. It has no `outputs` map — it spends coin by the
  /// hour and lands raws through a different path — so a test for outputs alone
  /// silently ignored a shed with three hands posted to it and coin going out
  /// every tick. It is as much a working shed as a sawmill; it simply produces
  /// by buying rather than by making.
  ///
  /// Hence [BuildingDef.isProducer], which is the codebase's existing answer to
  /// "does this draw hands and do something with them" — rather than a second
  /// hand-rolled version of the same question, which is how the Import Berth
  /// came to be missed in the first place.
  int get staffedSheds =>
      buildings.where((b) => b.workers > 0 && b.def.isProducer).length;

  bool canHire(Retainer r) =>
      r.level == levelOn(r.track) + 1 &&
      coin >= r.coinCost &&
      producingSheds >= r.requiresBuildings &&
      // Taking on a track you have nobody on needs a berth free.
      (levelOn(r.track) > 0 || hasFreeOfficerBerth);

  bool hire(Retainer r) {
    if (!canHire(r)) return false;
    coin -= r.coinCost;
    switch (r.track) {
      case RetinueTrack.captain:
        captainLevel = r.level;
      case RetinueTrack.merchant:
        merchantLevel = r.level;
      case RetinueTrack.quartermaster:
        quartermasterLevel = r.level;
    }
    log('${r.name}, ${r.title.toLowerCase()}, signed on at '
        '${r.dailyWage}c a day.', LogKind.good);
    journal.mark(
        day,
        'hired ${r.track.name} L${r.level} (${r.name}) '
        'for ${r.coinCost}c',
        // The retainer's proper name is a function of track and level via
        // kRetinue, so the code carries the track and level and lets the
        // decoder look the name up rather than shipping it.
        code: RunCode.hireMark(day, r.track.name, r.level, r.coinCost.round()));
    return true;
  }

  /// Let the whole track go, back to nobody. Stops the wage immediately.
  void dismiss(RetinueTrack t) {
    final who = hiredOn(t);
    if (who == null) return;
    switch (t) {
      case RetinueTrack.captain:
        captainLevel = 0;
      case RetinueTrack.merchant:
        merchantLevel = 0;
      case RetinueTrack.quartermaster:
        quartermasterLevel = 0;
    }
    log('${who.name} was paid off and left the port.', LogKind.info);
  }

  double get voyageSpeedFactor => hiredOn(RetinueTrack.captain)?.voyageSpeed ?? 1.0;
  double get voyageRiskFactor => hiredOn(RetinueTrack.captain)?.voyageRisk ?? 1.0;
  double get sellBonus => hiredOn(RetinueTrack.merchant)?.sellBonus ?? 1.0;
  double get voyagePayBonus => hiredOn(RetinueTrack.merchant)?.voyagePay ?? 1.0;

  /// The factor's cut of a sale at your own quay.
  double get quayCommission =>
      hiredOn(RetinueTrack.merchant)?.commission ?? 0.0;

  /// What one unit sold into [offer] actually puts in the strongbox.
  ///
  /// The single arithmetic for a quay sale, so the price the panel shows and
  /// the coin [sell] pays can never disagree.
  double quayNetPerUnit(Offer offer) =>
      offer.pricePerUnit *
      sellBonus *
      charters.salePrice *
      (1.0 - quayCommission);

  /// The cut taken from a consignment abroad. The captain shares in the
  /// venture as well as the factor, which is why a fast hull is not free.
  double get voyageCommission =>
      (hiredOn(RetinueTrack.merchant)?.commission ?? 0.0) +
      (hiredOn(RetinueTrack.captain)?.commission ?? 0.0);

  /// Tracks you currently have someone on, at any level.
  int get officersRetained =>
      RetinueTrack.values.where((t) => levelOn(t) > 0).length;

  int get officerCapacity => officerCapacityFor(staffedSheds);

  /// A new *track* needs a free berth on the books; promoting someone you
  /// already retain does not, since it is the same person paid better.
  bool get hasFreeOfficerBerth => officersRetained < officerCapacity;

  /// What the retinue costs you every day, on top of the crews' wages.
  int get retinueWageBill => RetinueTrack.values
      .fold(0, (sum, t) => sum + (hiredOn(t)?.dailyWage ?? 0));

  AutoCollect get autoCollectMode =>
      hiredOn(RetinueTrack.quartermaster)?.autoCollect ?? AutoCollect.none;

  /// Let the quartermaster do the carting.
  ///
  /// Runs while you are away as well as while you are watching: its whole job
  /// is that a shed never stands idle waiting on a tap, and being asleep is
  /// exactly when that would happen.
  void _runAutoCollect({required bool dayTurned}) {
    final mode = autoCollectMode;
    if (mode == AutoCollect.none) return;

    // Whoever you have hired, a full yard gets emptied — no shed of yours
    // stands idle because nobody was watching.
    for (final b in buildings) {
      if (b.holdFullness >= 0.999) collect(b);
    }

    switch (mode) {
      case AutoCollect.none:
        return;
      case AutoCollect.everyOtherDay:
        if (dayTurned && day.isEven) collectAll();
      case AutoCollect.daily:
        if (dayTurned) collectAll();
      case AutoCollect.hourly:
        collectAll();
    }
  }

  // ---- Progression -------------------------------------------------------

  bool isUnlocked(String buildingId) => unlocked.contains(buildingId);

  /// Whether a rule's conditions are satisfied right now.
  bool _unlockMet(UnlockRule r) {
    if (day < r.minDay) return false;
    if (coin < r.minCoin) return false;
    for (final id in r.requires) {
      if (!buildings.any((b) => b.defId == id)) return false;
    }
    for (final e in r.minStock.entries) {
      if (stock[e.key] < e.value) return false;
    }
    return true;
  }

  /// Check the tree and announce anything newly available. Called whenever the
  /// player does something that could plausibly have earned an unlock, so the
  /// moment lands next to the action that caused it.
  void checkUnlocks() {
    for (final r in kUnlockRules) {
      if (unlocked.contains(r.id)) continue;
      if (!_unlockMet(r)) continue;
      unlocked.add(r.id);
      final def = defById(r.id);
      log('${def.icon} You can now build a ${def.name.toLowerCase()}.',
          LogKind.good);
    }
  }

  bool canBuild(BuildingDef def) =>
      isUnlocked(def.id) &&
      coin >= def.coinCost &&
      stock.canAfford(def.cost);

  bool build(BuildingDef def) {
    if (!canBuild(def)) return false;
    coin -= def.coinCost;
    stock.payAll(def.cost);
    final b = Building(defId: def.id);
    autoPlace(b);
    buildings.add(b);
    log('${def.name} raised on the waterfront.', LogKind.good);
    journal.mark(day, 'built ${def.name} (${buildings.length} total)',
        // def.id, not def.name: ids are stable, display names get polished.
        code: RunCode.buildMark(day, def.id));
    checkUnlocks(); // raising one shed often reveals the next
    return true;
  }

  /// Sell up to [qty] units into [offer]. Returns coin earned.
  double sell(Ship ship, Offer offer, double qty) {
    final available = stock[offer.resource];
    final amount = [qty, available, offer.quantity]
        .reduce((a, b) => a < b ? a : b);
    if (amount <= 1e-6) return 0;

    stock.remove(offer.resource, amount);
    offer.quantity -= amount;
    final earned = amount * quayNetPerUnit(offer);
    coin += earned.round();

    if (offer.resource.isContraband) {
      darkEarned += earned;
      // The dark market is thin, so it moves further on less volume.
      market.applySalePressure(
          offer.resource, amount * Market.saleImpactScale / Market.contrabandImpactScale);
      _addHeat(
          amount * offer.resource.heatWeight * Balance.heatPerContrabandSold);
    } else {
      market.applySalePressure(offer.resource, amount);
      if (!ship.isFreeTrader) {
        // Honest commerce launders. The legitimate chains stay load-bearing
        // inside the risk layer instead of being obsoleted by it.
        final shed = earned * Balance.launderPerCoin;
        _addHeat(-(shed < Balance.launderCapPerSale
            ? shed
            : Balance.launderCapPerSale));
      }
    }

    log('Sold ${amount.round()} ${offer.resource.label.toLowerCase()} to the '
        '${ship.name} for ${earned.round()}c.', LogKind.good);
    return earned;
  }

  /// Swap contraband for raw materials at a parity coin cannot match in bulk.
  /// The loudest transaction in the game per unit, and the best deal.
  bool barter(Ship ship, Barter deal) {
    if (deal.taken) return false;
    if (!stock.has(deal.give, deal.giveQty)) return false;

    final room =
        (storageCapacity - stock[deal.take]).clamp(0.0, double.infinity);
    if (room < deal.takeQty) return false;

    stock.remove(deal.give, deal.giveQty);
    stock.add(deal.take, deal.takeQty);
    deal.taken = true;
    // What you received, less what you handed over, both at the going rate.
    darkEarned += deal.takeQty * market.priceOf(deal.take) -
        deal.giveQty * market.priceOf(deal.give);
    _addHeat(deal.giveQty * deal.give.heatWeight * Balance.heatPerBarterUnit);

    log('Traded ${deal.giveQty.round()} ${deal.give.label.toLowerCase()} to the '
        '${ship.name} for ${deal.takeQty.round()} '
        '${deal.take.label.toLowerCase()}.', LogKind.good);
    return true;
  }

  /// Worker-weighted mean readiness across every privateer berth.
  double get berthReadiness {
    var hands = 0;
    var weighted = 0.0;
    for (final b in buildings) {
      if (b.defId != 'privateer_berth' || b.workers == 0) continue;
      hands += b.workers;
      weighted += b.lastEfficiency * b.workers;
    }
    return hands == 0 ? 0.0 : weighted / hands;
  }

  /// Remaining lawful prize tonnage.
  int marqueTons = 0;
  bool get letterActive => marqueTons > 0;

  int prizesTaken = 0;

  bool get canBuyLetter => notoriety < Balance.letterHeatCeiling;

  Map<Resource, double> letterCost(int tons) => {
        Resource.sailcloth: tons * Balance.marqueSailclothPerTon,
        Resource.tools: tons * Balance.marqueToolsPerTon,
      };

  int letterCoinCost(int tons) => tons * Balance.marqueCoinPerTon;

  /// Buy lawful cover for [tons] of prize tonnage.
  ///
  /// The Admiralty refuses a port it already mistrusts, which is the fork: the
  /// Crown's commission, or the deep dark discount, never both.
  bool buyLetterOfMarque(int tons) {
    if (tons <= 0 || !canBuyLetter) return false;
    final coinCost = letterCoinCost(tons);
    final goods = letterCost(tons);
    if (coin < coinCost || !stock.canAfford(goods)) return false;

    coin -= coinCost;
    stock.payAll(goods);
    marqueTons += tons;
    log('The Admiralty sealed a Letter of Marque for $tons tons.',
        LogKind.good);
    return true;
  }

  /// Can this hull be boarded right now, and if not, why not.
  String? prizeBlocker(Ship ship) {
    if (!ship.foreign || ship.prizeTons <= 0) return 'Not a lawful target';
    if (berthCrew <= 0) return 'No crew at the privateer berth';
    if (stock[Resource.powder] < Balance.prizePowderCost) {
      return 'Needs ${Balance.prizePowderCost.round()} powder';
    }
    return null;
  }

  double prizeSuccessChance(Ship ship) {
    final covered = marqueTons >= ship.prizeTons;
    final crew = berthCrew < 4 ? berthCrew : 4;
    return (Balance.prizeBaseSuccess +
            Balance.prizeSuccessPerCrew * crew * berthReadiness +
            (covered ? Balance.prizeCoveredBonus : 0.0))
        .clamp(0.0, Balance.prizeSuccessCap);
  }

  /// Board a foreign hull at your own quay. Resolves this instant — there is
  /// no voyage, no timer, and nothing to wait for.
  bool takePrize(Ship ship) {
    if (prizeBlocker(ship) != null) return false;

    stock.remove(Resource.powder, Balance.prizePowderCost);
    final covered = marqueTons >= ship.prizeTons;
    final won = rng.next() < prizeSuccessChance(ship);

    if (covered) marqueTons -= ship.prizeTons;

    if (!won) {
      _addHeat(covered
          ? Balance.heatPerFailedBoardingCovered
          : Balance.heatPerFailedBoardingUncovered);
      market.ships.remove(ship);
      log('The boarding party was beaten back off the ${ship.name}.',
          LogKind.bad);
      return false;
    }

    // Draw the hold from the weighted prize table.
    final entries = Balance.prizeTable.entries.toList();
    final total = entries.fold(0, (s, e) => s + e.value);
    var landed = 0.0;
    var sold = 0.0;
    for (final e in entries) {
      final qty = ship.prizeTons * e.value / total;
      final room = (storageCapacity - stock[e.key]).clamp(0.0, double.infinity);
      final fits = qty < room ? qty : room;
      stock.add(e.key, fits);
      landed += fits;
      // Overflow is bought off you rather than destroyed, so a full shed never
      // turns a won fight into a loss.
      final spill = qty - fits;
      if (spill > 0) {
        sold += spill * market.priceOf(e.key) *
            Balance.prizeOverflowSaleMultiplier;
      }
    }
    if (sold > 0) coin += sold.round();

    if (!covered) {
      _addHeat(ship.prizeTons * Balance.heatPerUncoveredPrizeTon);
    }
    prizesTaken++;
    market.ships.remove(ship);

    final tail = sold > 0 ? ', and ${sold.round()}c for what would not fit' : '';
    log('Took the ${ship.name} as a prize: ${landed.round()} units'
        '$tail.${covered ? "" : " No Letter covered her."}', LogKind.good);
    return true;
  }

  /// Destroy contraband outright. Returns nothing, changes notoriety by zero.
  ///
  /// Its whole value is that it removes exposure instantly, converting a
  /// certain seizure into a clean inspection. The panic button costs you cargo
  /// and never coin.
  double scuttle(Resource r, double qty) {
    if (!r.isContraband) return 0;
    final amount = qty < stock[r] ? qty : stock[r];
    if (amount <= 1e-6) return 0;
    stock.remove(r, amount);
    log('Put ${amount.round()} ${r.label.toLowerCase()} over the side.',
        LogKind.warn);
    return amount;
  }

  /// Sell contraband to the Crown at a poor price. Generates no heat and sheds
  /// none. Contraband is never a trap you cannot walk out of — only ever a
  /// bad price.
  double declareToCustoms(Resource r, double qty) {
    if (!r.isContraband) return 0;
    final amount = qty < stock[r] ? qty : stock[r];
    if (amount <= 1e-6) return 0;

    final earned =
        amount * market.priceOf(r) * Balance.declaredSaleMultiplier;
    stock.remove(r, amount);
    coin += earned.round();
    market.applySalePressure(
        r, amount * Market.saleImpactScale / Market.contrabandImpactScale);
    log('Declared ${amount.round()} ${r.label.toLowerCase()} to the customs '
        'house for ${earned.round()}c.', LogKind.info);
    return earned;
  }

  /// The most units of [ware] this port could actually take on right now,
  /// bounded by coin, the ship's cargo, and free space in the sheds.
  double maxPurchasable(Offer ware) {
    final affordable = ware.pricePerUnit <= 0 ? 0.0 : coin / ware.pricePerUnit;
    final room = (storageCapacity - stock[ware.resource]).clamp(0.0, double.infinity);
    return [affordable, ware.quantity, room].reduce((a, b) => a < b ? a : b);
  }

  /// Buy up to [qty] units off a ship. Returns coin spent.
  double buy(Ship ship, Offer ware, double qty) {
    final amount = qty < maxPurchasable(ware) ? qty : maxPurchasable(ware);
    if (amount <= 1e-6) return 0;

    final cost = amount * ware.pricePerUnit;
    coin -= cost.round();
    if (coin < 0) coin = 0;
    stock.add(ware.resource, amount);
    ware.quantity -= amount;
    market.applyPurchasePressure(ware.resource, amount);

    log('Bought ${amount.round()} ${ware.resource.label.toLowerCase()} off the '
        '${ship.name} for ${cost.round()}c.', LogKind.info);
    return cost;
  }

  bool buildLighthouse() {
    if (!canBuildLighthouse) return false;
    coin -= lighthouseCoinCost;
    stock.payAll(lighthouseGoodsCost);
    // Capture the winning day BEFORE the flag closes recording, or the run's
    // last and most interesting row is the one row missing from it.
    _recordDay();
    lighthouseBuilt = true;
    journal.mark(day, 'LIGHTHOUSE LIT — population $population',
        code: RunCode.winMark(day, population));
    log('The Saltwind Light burns for the first time. The port is made.',
        LogKind.good);
    return true;
  }

  // ---- Persistence ------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'version': 2,
        'events': events.toJson(),
        // Quantised on write and compared at no finer precision anywhere,
        // because band lookups gate an rng draw and a 1e-5 round-trip
        // divergence could otherwise flip an inspection.
        'notoriety': double.parse(notoriety.toStringAsFixed(3)),
        'cutterInspectTick': cutterInspectTick,
        'marqueTons': marqueTons,
        'prizesTaken': prizesTaken,
        'growthProgress':
            double.parse(growthProgress.toStringAsFixed(3)),
        'contrabandSeized':
            double.parse(contrabandSeized.toStringAsFixed(3)),
        'voyages': voyages.map((v) => v.toJson()).toList(),
        'unlocked': unlocked.toList(),
        'charters': charters.ids,
        'captainLevel': captainLevel,
        'merchantLevel': merchantLevel,
        'quartermasterLevel': quartermasterLevel,
        'tick': tick,
        'stock': stock.toJson(),
        'coin': coin,
        'buildings': buildings.map((b) => b.toJson()).toList(),
        'population': population,
        'market': market.toJson(),
        'seed': rng.seed,
        'lighthouseBuilt': lighthouseBuilt,
        'victoryRecorded': victoryRecorded,
        'journal': journal.toJson(),
        'darkEarned': double.parse(darkEarned.toStringAsFixed(1)),
        'darkLost': double.parse(darkLost.toStringAsFixed(1)),
      };

  static GameState fromJson(Map<String, dynamic> j) {
    final state = GameState._(
      tick: (j['tick'] as num).toInt(),
      stock: ResourceBag.fromJson(j['stock'] as Map<String, dynamic>),
      coin: (j['coin'] as num).toInt(),
      buildings: (j['buildings'] as List)
          .map((b) => Building.fromJson(b as Map<String, dynamic>))
          .where((b) => kBuildingDefs.any((d) => d.id == b.defId))
          .toList(),
      population: (j['population'] as num).toInt(),
      market: Market.fromJson(j['market'] as Map<String, dynamic>),
      rng: SeededRng((j['seed'] as num).toInt()),
      lighthouseBuilt: j['lighthouseBuilt'] as bool? ?? false,
    );
    // Absent in a v1 save: a port that has never seen weather simply starts
    // its event clock from the grace period.
    state.events =
        EventSystem.fromJson(j['events'] as Map<String, dynamic>?);
    // All absent from a v1 save, which correctly describes an honest port.
    state.notoriety =
        ((j['notoriety'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 100.0);
    state.cutterInspectTick = (j['cutterInspectTick'] as num?)?.toInt() ?? -1;
    state.marqueTons = (j['marqueTons'] as num?)?.toInt() ?? 0;
    state.prizesTaken = (j['prizesTaken'] as num?)?.toInt() ?? 0;
    state.contrabandSeized =
        (j['contrabandSeized'] as num?)?.toDouble() ?? 0.0;
    state.growthProgress =
        (j['growthProgress'] as num?)?.toDouble() ?? 0.0;
    final saved = j['unlocked'] as List?;
    // A save from before the tree existed has seen everything already; taking
    // buildings away from an established port would be nonsense.
    state.unlocked.addAll(saved == null
        ? kBuildingDefs.map((d) => d.id)
        : saved.cast<String>());
    state.captainLevel = (j['captainLevel'] as num?)?.toInt() ?? 0;
    state.merchantLevel = (j['merchantLevel'] as num?)?.toInt() ?? 0;
    state.quartermasterLevel =
        (j['quartermasterLevel'] as num?)?.toInt() ?? 0;
    state.voyages.addAll((j['voyages'] as List? ?? [])
        .map((v) => Voyage.fromJson(v as Map<String, dynamic>))
        .whereType<Voyage>());
    state._clampAssignments();
    // A run keeps the charters it began under, so resuming cannot quietly
    // change the conditions you started playing on.
    state.charters =
        CharterSet.fromIds((j['charters'] as List? ?? []).cast<String>());
    state.victoryRecorded = j['victoryRecorded'] as bool? ?? false;
    state.journal =
        RunJournal.fromJson(j['journal'] as Map<String, dynamic>?);
    state.darkEarned = (j['darkEarned'] as num?)?.toDouble() ?? 0;
    state.darkLost = (j['darkLost'] as num?)?.toDouble() ?? 0;
    state.placeAll();
    state.syncYards();
    state._clampRetinueToBerths();
    return state;
  }

  /// Bring a loaded roster within the berth cap.
  ///
  /// Saves written before berths existed can hold all three tracks at a port
  /// that now supports one, and [canHire] only gates *new* tracks — so an
  /// over-cap roster would have gone on being promoted forever, exempt from a
  /// limit every later run has to live with. Officers are let go from the
  /// cheapest track up, so what survives is the investment the player made
  /// most heavily in.
  void _clampRetinueToBerths() {
    var over = officersRetained - officerCapacity;
    if (over <= 0) return;

    final held = RetinueTrack.values.where((t) => levelOn(t) > 0).toList()
      ..sort((a, b) =>
          (hiredOn(a)?.coinCost ?? 0).compareTo(hiredOn(b)?.coinCost ?? 0));

    for (final t in held) {
      if (over <= 0) break;
      final who = hiredOn(t);
      switch (t) {
        case RetinueTrack.captain:
          captainLevel = 0;
        case RetinueTrack.merchant:
          merchantLevel = 0;
        case RetinueTrack.quartermaster:
          quartermasterLevel = 0;
      }
      if (who != null) {
        log('${who.name} was let go — the port keeps $officerCapacity '
            'officer${officerCapacity == 1 ? "" : "s"}.', LogKind.info);
      }
      over--;
    }
  }
}
