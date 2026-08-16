/// A record of how a run actually went, for calibrating the balance bot.
///
/// WHY THIS EXISTS. `tool/balance_probe.dart` plays the game headlessly and is
/// the only way a balance change gets checked against more than one opinion.
/// It has also been wrong, twice, in ways only real play caught: it never sent
/// a consignment (so the first merchant measured as worthless, and a charter
/// that does nothing but lengthen crossings measured as zero difficulty), and
/// it underestimated early income badly enough to predict a first hire on day
/// 23 when a player managed day 13.
///
/// The fix for that is not more guessing. It is a trace of a real run, day by
/// day, that the bot's own trace can be laid against — so "the bot plays like a
/// human" becomes a thing you can check rather than a thing you assert.
///
/// Kept deliberately small: one short row per day plus the moments that matter.
/// A 200-day run is a few kilobytes, which survives in the save and pastes into
/// a message without ceremony.
library;

/// One day, as it stood at nightfall.
class JournalDay {
  const JournalDay({
    required this.day,
    required this.population,
    required this.coin,
    required this.buildings,
    required this.staffed,
    required this.foodDays,
    required this.atSea,
  });

  final int day;
  final int population;
  final int coin;
  final int buildings;

  /// Working sheds with hands in them — the bot's proxy for a real port.
  final int staffed;

  final double foodDays;

  /// Consignments away at nightfall. The bot sailed nothing at all until this
  /// journal made the gap obvious.
  final int atSea;

  /// One CSV row. Column order matches [JournalDay.header].
  String toCsv() => '$day,$population,$coin,$buildings,$staffed,'
      '${foodDays.toStringAsFixed(1)},$atSea';

  static const String header = 'day,pop,coin,built,staffed,foodDays,atSea';

  Map<String, dynamic> toJson() => {
        'd': day,
        'p': population,
        'c': coin,
        'b': buildings,
        's': staffed,
        'f': double.parse(foodDays.toStringAsFixed(1)),
        'v': atSea,
      };

  static JournalDay fromJson(Map<String, dynamic> j) => JournalDay(
        day: (j['d'] as num).toInt(),
        population: (j['p'] as num).toInt(),
        coin: (j['c'] as num).toInt(),
        buildings: (j['b'] as num).toInt(),
        staffed: (j['s'] as num?)?.toInt() ?? 0,
        foodDays: (j['f'] as num?)?.toDouble() ?? 0,
        atSea: (j['v'] as num?)?.toInt() ?? 0,
      );
}

/// Something worth knowing the day of: a build, a hire, a consignment, a win.
class JournalMark {
  const JournalMark(this.day, this.what);

  final int day;
  final String what;

  Map<String, dynamic> toJson() => {'d': day, 'w': what};

  static JournalMark fromJson(Map<String, dynamic> j) =>
      JournalMark((j['d'] as num).toInt(), j['w'] as String);
}

class RunJournal {
  RunJournal({List<JournalDay>? days, List<JournalMark>? marks})
      : days = days ?? [],
        marks = marks ?? [];

  final List<JournalDay> days;
  final List<JournalMark> marks;

  /// Long enough for any real run, short enough that the save stays small.
  static const int maxDays = 400;
  static const int maxMarks = 300;

  void record(JournalDay d) {
    if (days.length >= maxDays) return;
    days.add(d);
  }

  void mark(int day, String what) {
    if (marks.length >= maxMarks) return;
    marks.add(JournalMark(day, what));
  }

  /// A compact report, small enough to paste into a message.
  String report({
    required String charters,
    required int difficulty,
    required bool won,
  }) {
    final b = StringBuffer()
      ..writeln('# Ports Ahoy run report')
      ..writeln('charters: ${charters.isEmpty ? "none" : charters}')
      ..writeln('difficulty: $difficulty')
      ..writeln('outcome: ${won ? "lighthouse lit" : "in progress"}')
      ..writeln('days recorded: ${days.length}')
      ..writeln()
      ..writeln('## milestones');
    for (final m in marks) {
      b.writeln('day ${m.day}: ${m.what}');
    }
    b
      ..writeln()
      ..writeln('## daily')
      ..writeln(JournalDay.header);
    for (final d in days) {
      b.writeln(d.toCsv());
    }
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'days': days.map((d) => d.toJson()).toList(),
        'marks': marks.map((m) => m.toJson()).toList(),
      };

  static RunJournal fromJson(Map<String, dynamic>? j) {
    if (j == null) return RunJournal();
    return RunJournal(
      days: (j['days'] as List? ?? [])
          .map((d) => JournalDay.fromJson(d as Map<String, dynamic>))
          .toList(),
      marks: (j['marks'] as List? ?? [])
          .map((m) => JournalMark.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}
