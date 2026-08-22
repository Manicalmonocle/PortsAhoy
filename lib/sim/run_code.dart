/// PA1 — a whole run trace, small enough to ride inside a URL.
///
/// WHY THIS EXISTS. `RunJournal.report()` produces prose and CSV meant for a
/// human: a 200-day run is 7,463 characters, which becomes 11,549 once
/// URL-encoded. Measured against GitHub's own endpoint, 6,000 encoded
/// characters is accepted, 8,000 kills the connection outright and 12,000
/// returns 414. So the readable report cannot travel by link, by any route, to
/// anywhere. It is still the right thing to put on the clipboard; it is simply
/// the wrong thing to put in a query string.
///
/// Two rules shape the format:
///
/// 1. EVERY CHARACTER IS URL-SAFE. The separators are drawn only from
///    `- . _ ~`, which with the alphanumerics are RFC 3986 "unreserved" — the
///    only characters that survive BOTH `Uri.encodeComponent` and
///    `Uri.encodeQueryComponent` unchanged. That makes the encoded length equal
///    to the raw length, so the size budget can be checked directly instead of
///    guessed at. A comma or a newline would cost three characters each, and
///    separators are the single biggest cost in a format this repetitive: they
///    are most of why the readable report inflates by 55% when encoded.
///
/// 2. IT CARRIES NO FREE TEXT. The emitter reads only the structured [code] on
///    a mark, never `JournalMark.what`. `what` is an unconstrained String; if
///    anyone ever writes a player-supplied name or a place into one, a format
///    that interpolated it would quietly start shipping that off the device.
///    A test asserts the output matches `[A-Za-z0-9._~-]+`, so that mistake
///    fails the suite rather than a player's privacy.
///
/// Numbers are base-36 throughout. Not for the small saving on any one field,
/// but because one uniform rule for every integer is a great deal harder to
/// get wrong than a mixture of bases chosen per column.
library;

import 'journal.dart';

/// Base-36 keeps every integer to one rule, in both directions.
String _enc(int v) => v.toRadixString(36);
int _dec(String s) => int.parse(s, radix: 36);

/// Three letters, derived rather than tabulated.
///
/// A hand-written code table is a second place to update every time a building
/// is added, and the failure when someone forgets is silent — two buildings
/// share a code and the decoder mislabels one of them forever. Deriving them
/// means the only way to break it is a genuine collision, and
/// `run_code_test.dart` asserts there isn't one across every def and
/// destination in the game.
String shortCode(String s) {
  final letters = s.replaceAll(RegExp(r'[^A-Za-z]'), '').toLowerCase();
  return letters.length <= 3 ? letters : letters.substring(0, 3);
}

/// A run decoded back out of a PA1 string.
class DecodedRun {
  DecodedRun({
    required this.version,
    required this.seed,
    required this.difficulty,
    required this.charters,
    required this.won,
    required this.stride,
    required this.daysTruncated,
    required this.marksTruncated,
    required this.declaredDays,
    required this.unattendedDays,
    required this.lighthouseCoinNeeded,
    required this.lighthouseHave,
    required this.lostInTransit,
    required this.marks,
    required this.days,
  });

  final String version;
  final int seed;
  final int difficulty;
  final List<String> charters;
  final bool won;

  /// Days between successive rows. 1 means every day was kept.
  final int stride;

  /// The journal stopped recording before the run ended. Set when a run
  /// outlives [RunJournal.maxDays] / [RunJournal.maxMarks] — without this the
  /// tail of a long run looks like a port that stopped building and stopped
  /// sailing, which is a conclusion about balance rather than about storage.
  final bool daysTruncated;
  final bool marksTruncated;

  /// How many days the sending device said this run had.
  final int declaredDays;

  /// How many of those ran while the app was closed. The game ticks in the
  /// background, so a long run can contain stretches nobody played — and the
  /// bot this is compared against plays every day actively.
  final int unattendedDays;

  /// Coin the lighthouse wanted in this run, charters included, and what the
  /// stores held of each good it asks for (keyed by three-letter code). Null
  /// and empty on reports written before this was recorded.
  final int? lighthouseCoinNeeded;
  final Map<String, int> lighthouseHave;

  /// Fewer rows arrived than [declaredDays] implies — the payload was cut in
  /// transit. Distinct from [daysTruncated], which is the journal hitting its
  /// own cap on the phone: that one is a known limit, this one is damage.
  final bool lostInTransit;

  final List<DecodedMark> marks;
  final List<JournalDay> days;

  /// Back to the same CSV shape `RunJournal.report()` emits, so a decoded run
  /// and a natively-recorded one can be compared without special-casing.
  String toCsv() {
    final b = StringBuffer()..writeln(JournalDay.header);
    for (final d in days) {
      b.writeln(d.toCsv());
    }
    return b.toString();
  }
}

/// A milestone, decoded. [kind] is one of build/hire/voyage/win.
class DecodedMark {
  DecodedMark(this.day, this.kind, this.fields);

  final int day;
  final String kind;

  /// Kind-specific values, already parsed. Deliberately a map rather than four
  /// subclasses: the consumer is a calibration script, not the game.
  final Map<String, Object> fields;

  @override
  String toString() => 'day $day: $kind $fields';
}

class RunCode {
  static const String prefix = 'PA1';

  /// Strides tried in order until the payload fits. Days are the last thing
  /// thinned and never below every-other-day, because coin is spiky and the
  /// spikes are the decisions being dated — thinning them past N=2 blurs the
  /// exact thing the trace exists to measure.
  static const List<int> strides = [1, 2, 3, 5, 10];

  /// Encode [j] as a PA1 string of at most [maxChars] characters.
  ///
  /// Degrades by widening the stride rather than by failing: a run long enough
  /// to overflow is still worth most of its signal, and a caller that got an
  /// exception here would have nothing to offer the player at all.
  static String encode(
    RunJournal j, {
    required String version,
    required int seed,
    required int difficulty,
    required List<String> charters,
    required bool won,
    LighthouseState? lighthouse,
    int maxChars = 5500,
  }) {
    String build(int stride) {
      final head = [
        prefix,
        // '+' is not unreserved, and pubspec versions always contain one.
        version.replaceAll('+', '-'),
        _enc(seed),
        _enc(difficulty),
        charters.join('-'),
        won ? '1' : '0',
        _enc(j.days.length),
        (j.daysTruncated ? 1 : 0) + (j.marksTruncated ? 2 : 0),
        _enc(stride),
        _enc(j.unattendedDays),
      ].join('~');

      final marks = <String>[];
      for (final m in j.marks) {
        final c = m.code;
        if (c == null) continue; // never fall back to free text
        marks.add(c);
      }

      final rows = <String>[];
      for (var i = 0; i < j.days.length; i += stride) {
        final d = j.days[i];
        rows.add([
          _enc(d.population),
          _enc(d.coin),
          _enc(d.buildings),
          _enc(d.staffed),
          _enc((d.foodDays * 10).round()),
          _enc(d.atSea),
        ].join('.'));
      }

      // What the light still wants, and what is in the stores for it.
      //
      // Added because a player reported "can't raise lighthouse" and the
      // report could not answer it: it carries population and coin but no
      // goods, so the one question a stuck run asks was the one question the
      // trace could not settle.
      final light = lighthouse == null
          ? ''
          : '~L${[
              _enc(lighthouse.coinNeeded),
              ...lighthouse.have.entries
                  .map((e) => '${shortCode(e.key)}${_enc(e.value.round())}'),
            ].join('.')}';

      return '$head$light~M${marks.join('_')}~D${rows.join('_')}';
    }

    for (final s in strides) {
      final out = build(s);
      if (out.length <= maxChars) return out;
    }
    return build(strides.last);
  }

  static DecodedRun decode(String s) {
    final parts = s.trim().split('~');
    if (parts.length < 11 || parts[0] != prefix) {
      throw FormatException('not a PA1 run code', s);
    }
    final flags = int.parse(parts[7]);
    final stride = _dec(parts[8]);

    // Located by their marker, not by position. Every other field is base-36
    // or lowercase, so an uppercase M or D can only be a section head — and
    // finding them this way means adding a header field later cannot silently
    // shift the parse onto the wrong data.
    final markField = parts.firstWhere((p) => p.startsWith('M'),
        orElse: () => throw FormatException('PA1 has no milestone section', s));
    final dayField = parts.firstWhere((p) => p.startsWith('D'),
        orElse: () => throw FormatException('PA1 has no daily section', s));

    final headerFields = parts.indexOf(markField);
    final unattended =
        headerFields > 9 && !parts[9].startsWith('L') ? _dec(parts[9]) : 0;

    final lightField = parts.firstWhere((p) => p.startsWith('L'),
        orElse: () => '');
    int? coinNeeded;
    final have = <String, int>{};
    if (lightField.isNotEmpty) {
      final f = lightField.substring(1).split('.');
      coinNeeded = _dec(f.first);
      for (final part in f.skip(1)) {
        final m = RegExp(r'^([a-z]{1,3})([0-9a-z]+)$').firstMatch(part);
        if (m != null) have[m.group(1)!] = _dec(m.group(2)!);
      }
    }

    final marks = <DecodedMark>[];
    for (final raw in markField.substring(1).split('_')) {
      if (raw.isEmpty) continue;
      marks.add(_decodeMark(raw));
    }

    final days = <JournalDay>[];
    final rows = dayField.substring(1).split('_');
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].isEmpty) continue;
      final f = rows[i].split('.');
      if (f.length != 6) {
        // A cut arrives mid-row far more often than on a boundary, so a
        // half-row at the very end is the ordinary shape of truncation, not
        // corruption. Drop it and keep everything before it — throwing here
        // would discard a report that is 95% intact. Anywhere else it is a
        // real format error and worth failing on.
        if (i == rows.length - 1) break;
        throw FormatException('bad PA1 row', rows[i]);
      }
      days.add(JournalDay(
        // The day column is not stored: it is position times stride. Storing
        // it would repeat information the row's own index already carries.
        day: i * stride + 1,
        population: _dec(f[0]),
        coin: _dec(f[1]),
        buildings: _dec(f[2]),
        staffed: _dec(f[3]),
        foodDays: _dec(f[4]) / 10.0,
        atSea: _dec(f[5]),
      ));
    }

    // The header declares how many days the run had. If fewer rows arrived
    // than that implies, the payload was cut somewhere between the player's
    // phone and here — a mail client with a URL limit, a chat app wrapping a
    // long line, a copy that missed the end.
    //
    // This is the check that makes sending by email defensible at all.
    // Without it a clipped report is indistinguishable from a short run, and
    // the analysis silently reads a truncation as a player who stopped
    // playing. Loud beats subtle: a decoder that shouts is recoverable, a
    // number that quietly lies is not.
    final declared = _dec(parts[6]);
    final expected = stride <= 1 ? declared : (declared + stride - 1) ~/ stride;

    return DecodedRun(
      version: parts[1],
      seed: _dec(parts[2]),
      difficulty: _dec(parts[3]),
      charters: parts[4].isEmpty ? const [] : parts[4].split('-'),
      won: parts[5] == '1',
      stride: stride,
      daysTruncated: flags & 1 != 0,
      marksTruncated: flags & 2 != 0,
      declaredDays: declared,
      unattendedDays: unattended,
      lighthouseCoinNeeded: coinNeeded,
      lighthouseHave: have,
      lostInTransit: days.length < expected,
      marks: marks,
      days: days,
    );
  }

  static DecodedMark _decodeMark(String raw) {
    final kind = raw[0];
    final f = raw.substring(1).split('.');
    switch (kind) {
      case 'b':
        return DecodedMark(_dec(f[0]), 'build', {'building': f[1]});
      case 'h':
        return DecodedMark(_dec(f[0]), 'hire', {
          'track': f[1][0],
          'level': int.parse(f[1].substring(1)),
          'coin': _dec(f[2]),
        });
      case 'v':
        return DecodedMark(_dec(f[0]), 'voyage', {
          'units': _dec(f[1]),
          'destination': f[2],
          // Tenths of a day. The crossing length is the only direct
          // measurement of what a difficulty charter actually costs, and it
          // used to live in prose where a parser would read it as zero.
          'days': _dec(f[3]) / 10.0,
          'quote': _dec(f[4]),
        });
      case 'p':
        return DecodedMark(_dec(f[0]), 'prize', {
          'tons': _dec(f[1]),
          'spiceHeld': f.length > 2 ? _dec(f[2]) : 0,
        });
      case 'W':
        return DecodedMark(_dec(f[0]), 'win', {'population': _dec(f[1])});
      default:
        throw FormatException('unknown PA1 mark', raw);
    }
  }

  /// Mark codes, built where the events happen.
  static String buildMark(int day, String buildingId) =>
      'b${_enc(day)}.${shortCode(buildingId)}';

  static String hireMark(int day, String track, int level, int coin) =>
      'h${_enc(day)}.${track[0]}$level.${_enc(coin)}';

  static String voyageMark(
          int day, int units, String destination, double days, int quote) =>
      'v${_enc(day)}.${_enc(units)}.${shortCode(destination)}'
      '.${_enc((days * 10).round())}.${_enc(quote)}';

  /// A boarded hull: tonnage taken, and the spice held afterwards.
  static String prizeMark(int day, int tons, int spiceHeld) =>
      'p${_enc(day)}.${_enc(tons)}.${_enc(spiceHeld)}';

  static String winMark(int day, int population) =>
      'W${_enc(day)}.${_enc(population)}';
}


/// What the light is asking for, at the moment a report is written.
class LighthouseState {
  const LighthouseState({required this.coinNeeded, required this.have});

  /// Charter-scaled, so it is the figure the game actually enforces rather
  /// than the base one. Showing the base cost is precisely the bug that made
  /// this worth recording.
  final int coinNeeded;

  /// Stock of each good the light wants, keyed by resource label.
  final Map<String, double> have;
}
