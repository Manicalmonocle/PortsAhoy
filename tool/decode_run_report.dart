// Turn PA1 run codes back into readable traces.
//
// A collection pipeline that delivers strings nobody can read is not a
// pipeline. This is the other half of lib/sim/run_code.dart: point it at what
// testers sent and get back the same CSV shape the in-game report produces, so
// a real run and a bot run can be compared without special-casing either.
//
//   dart run tool/decode_run_report.dart PA1~1.0.8-9~...      # one code
//   dart run tool/decode_run_report.dart reports.csv          # a file of them
//   pbpaste | dart run tool/decode_run_report.dart            # stdin
//
// A Google Sheets export works directly: any PA1~ token found anywhere in the
// file is decoded, whatever quoting or extra columns surround it.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:ports_ahoy/sim/run_code.dart';

/// PA1 uses only unreserved characters, so a run code is exactly one token.
final _codePattern = RegExp(r'PA1~[A-Za-z0-9._~-]+');

void main(List<String> args) {
  final haystack = StringBuffer();

  if (args.isEmpty) {
    for (String? line = stdin.readLineSync();
        line != null;
        line = stdin.readLineSync()) {
      haystack.writeln(line);
    }
  } else {
    for (final a in args) {
      final f = File(a);
      haystack.write(f.existsSync() ? f.readAsStringSync() : a);
      haystack.write('\n');
    }
  }

  final codes =
      _codePattern.allMatches(haystack.toString()).map((m) => m.group(0)!).toList();

  if (codes.isEmpty) {
    stderr.writeln('No PA1 run codes found. A code starts with "PA1~".');
    exit(1);
  }

  for (var i = 0; i < codes.length; i++) {
    if (i > 0) print('');
    try {
      _print(codes[i], i + 1, codes.length);
    } on FormatException catch (e) {
      // One malformed submission must not cost you the rest of the batch.
      stderr.writeln('report ${i + 1}: could not decode — ${e.message}');
    }
  }
}

void _print(String code, int n, int total) {
  final r = RunCode.decode(code);

  print('=== report $n of $total ===');
  print('build:      ${r.version}');
  print('seed:       ${r.seed}');
  print('charters:   ${r.charters.isEmpty ? "none" : r.charters.join(", ")}');
  print('difficulty: ${r.difficulty}');
  print('outcome:    ${r.won ? "lighthouse lit" : "unfinished"}');
  print('days:       ${r.days.length}'
      '${r.stride > 1 ? " (every ${r.stride} days — run was too long to send in full)" : ""}');
  if (r.daysTruncated || r.marksTruncated) {
    print('WARNING:    the journal stopped recording before the run ended. '
        'The quiet tail is missing data, not a quiet port.');
  }

  // The two numbers the bot has been provably wrong about, so they are worth
  // reading off directly rather than hunting for in the table.
  final firstHire = r.marks.where((m) => m.kind == 'hire');
  final firstVoyage = r.marks.where((m) => m.kind == 'voyage');
  print('first hire: ${firstHire.isEmpty ? "never" : "day ${firstHire.first.day}"}');
  print('first sail: ${firstVoyage.isEmpty ? "never" : "day ${firstVoyage.first.day}"}');

  print('');
  print('## milestones');
  for (final m in r.marks) {
    print('day ${m.day}: ${m.kind} ${m.fields}');
  }

  print('');
  print('## daily');
  stdout.write(r.toCsv());
}
