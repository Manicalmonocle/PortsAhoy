// Aggregate many run reports into one balance picture.
//
// `decode_run_report.dart` renders a single trace, which is the right tool when
// a report arrives and you want to read it. It is the wrong tool once several
// people are sending them: reading twenty runs one at a time tells you twenty
// stories and no pattern, and the patterns are the point.
//
//   dart run tool/survey_reports.dart                        # incoming/
//   dart run tool/survey_reports.dart path/to/dir_or_files
//
// WHAT IT IS LOOKING FOR. Mostly the bottleneck: at the moment a run wins, the
// requirement it finished closest to is the one that actually gated it, and the
// ones it finished swimming in were never really asked for. One run says little
// — the same port has come in 2 tools spare on one run and 165 spare on the
// next — but across a spread of players and seeds, which requirement binds and
// how often is exactly the number a bill is tuned against.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:ports_ahoy/sim/charters.dart';
import 'package:ports_ahoy/sim/game_state.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:ports_ahoy/sim/run_code.dart';

final _codePattern = RegExp(r'PA1~[A-Za-z0-9._~-]+');

/// The three-letter keys a PA1 payload uses for the lighthouse's goods.
String _key(Resource r) => r.name.length <= 3
    ? r.name.toLowerCase()
    : r.name.substring(0, 3).toLowerCase();

void main(List<String> args) {
  final paths = args.isEmpty ? ['tool/reference_runs/incoming'] : args;
  final haystack = StringBuffer();

  for (final p in paths) {
    final dir = Directory(p);
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.pa1') ||
            f.path.endsWith('.csv') ||
            f.path.endsWith('.txt')) {
          haystack.writeln(f.readAsStringSync());
        }
      }
      continue;
    }
    final f = File(p);
    if (f.existsSync()) haystack.writeln(f.readAsStringSync());
  }

  final seen = <String>{};
  final runs = <DecodedRun>[];
  for (final m in _codePattern.allMatches(haystack.toString())) {
    final code = m.group(0)!;
    if (!seen.add(code)) continue; // the same run can arrive twice
    try {
      runs.add(RunCode.decode(code));
    } catch (_) {
      // A truncated or malformed payload is worth knowing about but must not
      // stop the survey — one bad row should never cost you the other twenty.
      stderr.writeln('skipped an unreadable code (${code.length} chars)');
    }
  }

  if (runs.isEmpty) {
    stderr.writeln('No readable run codes found in: ${paths.join(", ")}');
    exit(1);
  }

  print('=' * 66);
  print('${runs.length} run${runs.length == 1 ? "" : "s"}');
  print('=' * 66);

  _byBuild(runs);
  _outcomes(runs);
  _bottlenecks(runs);
  _routes(runs);
  _integrity(runs);
}

void _byBuild(List<DecodedRun> runs) {
  final byBuild = <String, List<DecodedRun>>{};
  for (final r in runs) {
    byBuild.putIfAbsent(r.version, () => []).add(r);
  }
  final builds = byBuild.keys.toList()..sort();

  print('');
  print('## by build');
  print('build            n   won   days (min/median/max)');
  for (final b in builds) {
    final rs = byBuild[b]!;
    final won = rs.where((r) => r.won).toList();
    final days = won.map((r) => r.declaredDays).toList()..sort();
    final span = days.isEmpty
        ? '—'
        : '${days.first} / ${days[days.length ~/ 2]} / ${days.last}';
    print('${b.padRight(16)} ${rs.length.toString().padLeft(2)}'
        '   ${won.length.toString().padLeft(3)}   $span');
  }
}

void _outcomes(List<DecodedRun> runs) {
  final won = runs.where((r) => r.won).toList();
  print('');
  print('## outcomes');
  print('won ${won.length} of ${runs.length}');

  final byDiff = <int, List<DecodedRun>>{};
  for (final r in runs) {
    byDiff.putIfAbsent(r.difficulty, () => []).add(r);
  }
  final diffs = byDiff.keys.toList()..sort();
  for (final d in diffs) {
    final rs = byDiff[d]!;
    final w = rs.where((r) => r.won).map((r) => r.declaredDays).toList()..sort();
    print('  difficulty $d: ${rs.length} run(s), '
        '${w.isEmpty ? "none won" : "median ${w[w.length ~/ 2]} days"}');
  }
}

/// Which requirement each winning run finished closest to.
///
/// The surplus is what was left AFTER the bill was paid, so a run that ends on
/// 2 tools was two units from not winning that day, while 160 sailcloth against
/// a requirement of 90 means the weaver spent the back half making something
/// nobody was waiting for.
void _bottlenecks(List<DecodedRun> runs) {
  final binds = <String, int>{};
  final surpluses = <String, List<double>>{};
  var counted = 0;

  for (final r in runs.where((r) => r.won)) {
    if (r.lighthouseHave.isEmpty) continue;
    final scale = CharterSet.fromIds(r.charters).lighthouseCost;

    String? tightest;
    var tightestRatio = double.infinity;
    for (final entry in Balance.lighthouseCost.entries) {
      final need = entry.value * scale;
      if (need <= 0) continue;
      final have = (r.lighthouseHave[_key(entry.key)] ?? 0).toDouble();
      // Surplus as a share of the requirement, so 20 planks spare on a bill of
      // 160 ranks against 20 tools spare on a bill of 80 fairly.
      final ratio = have / need;
      surpluses.putIfAbsent(entry.key.label, () => []).add(ratio);
      if (ratio < tightestRatio) {
        tightestRatio = ratio;
        tightest = entry.key.label;
      }
    }
    if (tightest != null) {
      binds[tightest] = (binds[tightest] ?? 0) + 1;
      counted++;
    }
  }

  if (counted == 0) {
    print('');
    print('## bottlenecks — no run carried a lighthouse section');
    return;
  }

  print('');
  print('## what actually gated the win  ($counted run(s))');
  final ranked = binds.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in ranked) {
    final pct = (e.value / counted * 100).round();
    print('  ${e.key.padRight(10)} bound ${e.value} run(s)  ($pct%)');
  }

  print('');
  print('## typical surplus left over, as a share of the requirement');
  print('   (1.0x means finished with exactly the bill again in store)');
  final names = surpluses.keys.toList()..sort();
  for (final n in names) {
    final v = surpluses[n]!..sort();
    final med = v[v.length ~/ 2];
    final flag = med > 1.0
        ? '   <- overshooting; the bill is not what limits this'
        : med < 0.15
            ? '   <- came in on fumes'
            : '';
    print('  ${n.padRight(10)} ${med.toStringAsFixed(2)}x$flag');
  }
}

/// Which optional routes people actually took.
void _routes(List<DecodedRun> runs) {
  const dark = {'dis', 'bon', 'pow', 'pri'};
  var withGrange = 0, withAnyDark = 0, withBerth = 0, tookPrize = 0;
  var prizeTotal = 0;

  for (final r in runs) {
    final built = r.marks
        .where((m) => m.kind == 'build')
        .map((m) => '${m.fields['building']}')
        .toSet();
    if (built.contains('gra')) withGrange++;
    if (built.intersection(dark).isNotEmpty) withAnyDark++;
    if (built.contains('pri')) withBerth++;
    final prizes = r.marks.where((m) => m.kind == 'prize').length;
    if (prizes > 0) tookPrize++;
    prizeTotal += prizes;
  }

  print('');
  print('## routes taken');
  print('  grange built        $withGrange of ${runs.length}');
  print('  any dark shed       $withAnyDark of ${runs.length}');
  print('  privateer berth     $withBerth of ${runs.length}');
  print('  boarded at least 1  $tookPrize of ${runs.length}'
      '   ($prizeTotal prize(s) in total)');
}

/// Reports that cannot be trusted, and why.
void _integrity(List<DecodedRun> runs) {
  final lost = runs.where((r) => r.lostInTransit).length;
  final cut = runs.where((r) => r.daysTruncated || r.marksTruncated).length;
  final idle = runs.where((r) => r.unattendedDays > 0).toList();

  if (lost == 0 && cut == 0 && idle.isEmpty) return;

  print('');
  print('## read these with care');
  if (lost > 0) {
    print('  $lost report(s) arrived short — the payload was cut in transit');
  }
  if (cut > 0) {
    print('  $cut report(s) hit the journal cap on the phone');
  }
  if (idle.isNotEmpty) {
    // A port left running unattended is the difference between a slow run and
    // a run that was not being played. Day counts from these mean little.
    final worst =
        idle.map((r) => r.unattendedDays).reduce((a, b) => a > b ? a : b);
    print('  ${idle.length} report(s) include unattended days '
        '(worst: $worst) — day counts there are not pacing data');
  }
}
