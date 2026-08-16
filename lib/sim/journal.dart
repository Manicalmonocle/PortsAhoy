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
  const JournalMark(this.day, this.what, {this.code});

  final int day;

  /// Prose, for a person reading the report.
  final String what;

  /// The same event in machine form — see `run_code.dart`. Kept separate from
  /// [what] rather than parsed back out of it, for two reasons. Display copy
  /// gets polished (`built Sawmill (4 total)` is one rewording away from
  /// breaking a parser), and [what] is an unconstrained String that could one
  /// day carry something a player typed. Anything that travels off the device
  /// is built from [code] alone.
  final String? code;

  Map<String, dynamic> toJson() => {
        'd': day,
        'w': what,
        if (code != null) 'k': code,
      };

  static JournalMark fromJson(Map<String, dynamic> j) => JournalMark(
        (j['d'] as num).toInt(),
        j['w'] as String,
        code: j['k'] as String?,
      );
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

  /// The caps were hit and recording stopped.
  ///
  /// These used to be silent. A run that outlived them produced a report whose
  /// tail showed a port that had stopped building and stopped sailing — which
  /// reads as a finding about late-game balance rather than as the storage
  /// limit it actually is. Anyone analysing that trace would draw a real
  /// conclusion from an artefact. Cheaper to say so than to be misled.
  bool daysTruncated = false;
  bool marksTruncated = false;

  void record(JournalDay d) {
    if (days.length >= maxDays) {
      daysTruncated = true;
      return;
    }
    days.add(d);
  }

  void mark(int day, String what, {String? code}) {
    if (marks.length >= maxMarks) {
      marksTruncated = true;
      return;
    }
    marks.add(JournalMark(day, what, code: code));
  }

  /// A compact report, small enough to paste into a message.
  String report({
    required String charters,
    required int difficulty,
    required bool won,
    String version = 'unknown',
  }) {
    final b = StringBuffer()
      ..writeln('# Ports Ahoy run report')
      ..writeln('build: $version')
      ..writeln('charters: ${charters.isEmpty ? "none" : charters}')
      ..writeln('difficulty: $difficulty')
      ..writeln('outcome: ${won ? "lighthouse lit" : "in progress"}')
      ..writeln('days recorded: ${days.length}');
    if (daysTruncated || marksTruncated) {
      b.writeln('TRUNCATED: this run outgrew the journal '
          '(${daysTruncated ? "days" : ""}'
          '${daysTruncated && marksTruncated ? " and " : ""}'
          '${marksTruncated ? "milestones" : ""}). '
          'The trace stops early — it is not that the port went quiet.');
    }
    b
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
        if (daysTruncated) 'td': true,
        if (marksTruncated) 'tm': true,
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
    )
      // Survives a save/load, or a long run reloaded on a phone would forget
      // that its own tail is missing.
      ..daysTruncated = j['td'] == true
      ..marksTruncated = j['tm'] == true;
  }
}
