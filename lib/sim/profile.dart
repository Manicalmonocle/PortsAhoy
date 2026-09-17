/// What survives a run.
///
/// The game save is per-run and is thrown away when you start another. This is
/// the layer above it: the charters you have earned, the ones in force, and
/// what your ports have achieved. Stored separately so beginning a new voyage
/// never touches it.
library;

import 'charters.dart';

class RunRecord {
  const RunRecord({
    required this.days,
    required this.difficulty,
    required this.population,
    required this.charterIds,
  });

  final int days;

  /// Total hardship weight carried. Records are kept per difficulty, so a
  /// fast run under heavy weather is not competing with an easy one.
  final int difficulty;

  final int population;
  final List<String> charterIds;

  Map<String, dynamic> toJson() => {
        'days': days,
        'difficulty': difficulty,
        'population': population,
        'charters': charterIds,
      };

  static RunRecord fromJson(Map<String, dynamic> j) => RunRecord(
        days: (j['days'] as num).toInt(),
        difficulty: (j['difficulty'] as num?)?.toInt() ?? 0,
        population: (j['population'] as num?)?.toInt() ?? 0,
        charterIds: (j['charters'] as List? ?? []).cast<String>().toList(),
      );
}

class Profile {
  Profile({
    Set<String>? owned,
    Set<String>? active,
    List<RunRecord>? runs,
    this.pendingChoice = const [],
  })  : owned = owned ?? {},
        active = active ?? {},
        runs = runs ?? [];

  /// Charters earned. Permanent.
  final Set<String> owned;

  /// Charters in force for the next (or current) run.
  final Set<String> active;

  /// Every completed run, newest last.
  final List<RunRecord> runs;

  /// Charters offered but not yet chosen between, after a victory.
  List<String> pendingChoice;

  int get wins => runs.length;
  bool get hasChoicePending => pendingChoice.isNotEmpty;

  CharterSet get activeSet => CharterSet.fromIds(active);

  /// Best completion at each difficulty, so a hard run has its own ladder.
  Map<int, RunRecord> get bestByDifficulty {
    final out = <int, RunRecord>{};
    for (final r in runs) {
      final prev = out[r.difficulty];
      if (prev == null ||
          r.days < prev.days ||
          // Same day count: the larger port is the better showing. Without a
          // tiebreak the first run always won and the card could go on showing
          // a smaller town than one you had just bettered it with.
          (r.days == prev.days && r.population > prev.population)) {
        out[r.difficulty] = r;
      }
    }
    return out;
  }

  RunRecord? get best {
    if (runs.isEmpty) return null;
    return runs.reduce((a, b) => a.days <= b.days ? a : b);
  }

  /// Three charters you do not own yet, to choose between after a win.
  ///
  /// Deterministic in [seed] so the offer cannot be rerolled by closing the
  /// app — the choice is meant to be a decision, not a slot machine.
  ///
  /// ALWAYS AT LEAST ONE OF EACH KIND, when both are still available. A flat
  /// draw from a pool of 9 hardships and 8 advantages leaves an 8.2% chance of
  /// offering three advantages and nothing else, and a player hit it: "the
  /// charters all made the next run easier, none more difficult".
  ///
  /// That is not merely dull, it is a dead offer. Hardships *earn* the budget
  /// that advantages *spend* ([CharterSet.isLegal]), so a hand of three
  /// advantages hands you nothing you can afford to turn on and no way to pay
  /// for it later. Guaranteeing one of each makes every offer the trade the
  /// system is actually built on: take on a difficulty to fund a comfort.
  List<String> offer(int seed) {
    final pool = kCharters.where((c) => !owned.contains(c.id)).toList();
    if (pool.isEmpty) return const [];
    pool.sort((a, b) => a.id.compareTo(b.id));

    var s = seed & 0x7FFFFFFF;
    int next() => s = (s * 1103515245 + 12345) & 0x7FFFFFFF;

    final picked = <String>[];
    final taken = <String>{};

    /// Take one at random from [from], if it has anything left to give.
    void drawFrom(List<Charter> from) {
      final left = from.where((c) => !taken.contains(c.id)).toList();
      if (left.isEmpty) return;
      final c = left[next() % left.length];
      taken.add(c.id);
      picked.add(c.id);
    }

    // Order matters for determinism, not for fairness: the hardship is drawn
    // first so an identical seed always yields an identical offer.
    drawFrom(pool.where((c) => c.isHardship).toList());
    drawFrom(pool.where((c) => !c.isHardship).toList());
    while (picked.length < 3 && taken.length < pool.length) {
      drawFrom(pool);
    }
    // Sorted so the guaranteed pair never sits in a giveaway position.
    picked.sort();
    return picked;
  }

  /// Drop active charters until the selection is affordable again.
  ///
  /// The dearest advantage goes first, which settles the overage in the fewest
  /// removals and so takes the least away from the player. (The comment here
  /// used to claim the opposite of what the code did — it said cheapest-first
  /// while sorting dearest-first. The behaviour was the better of the two, so
  /// the description was what needed correcting.)
  void reconcile() {
    active.removeWhere((id) => !owned.contains(id));
    while (!activeSet.isLegal) {
      final advantages = activeSet.active.where((c) => !c.isHardship).toList()
        ..sort((a, b) => a.weight.compareTo(b.weight)); // -2 before -1
      if (advantages.isEmpty) break;
      active.remove(advantages.first.id);
    }
  }

  Map<String, dynamic> toJson() => {
        'owned': owned.toList(),
        'active': active.toList(),
        'runs': runs.map((r) => r.toJson()).toList(),
        'pending': pendingChoice,
      };

  static Profile fromJson(Map<String, dynamic>? j) {
    if (j == null) return Profile();
    return Profile(
      owned: (j['owned'] as List? ?? []).cast<String>().toSet(),
      active: (j['active'] as List? ?? []).cast<String>().toSet(),
      runs: (j['runs'] as List? ?? [])
          .map((r) => RunRecord.fromJson(r as Map<String, dynamic>))
          .toList(),
      pendingChoice: (j['pending'] as List? ?? []).cast<String>().toList(),
    )..reconcile();
  }
}
