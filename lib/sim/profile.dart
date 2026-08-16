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
  List<String> offer(int seed) {
    final pool = kCharters.where((c) => !owned.contains(c.id)).toList();
    if (pool.isEmpty) return const [];
    pool.sort((a, b) => a.id.compareTo(b.id));

    final picked = <String>[];
    var s = seed & 0x7FFFFFFF;
    final taken = <int>{};
    while (picked.length < 3 && taken.length < pool.length) {
      s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
      final i = s % pool.length;
      if (taken.add(i)) picked.add(pool[i].id);
    }
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
