// Lay the balance bot's run against a real person's and print the gap.
//
// WHY THIS EXISTS. "The bot plays like a human" has been asserted for the whole
// life of this project and has been wrong every time it was checked — it never
// sent a consignment, it underestimated early income by ~40%, and it takes 50
// days longer to win the same game. The reason it kept being wrong is that
// nothing measured it: the probe reported only on itself, so its own opinion of
// its pacing was the only evidence there was.
//
// This turns that into a number. Both sides are PA1 run codes — the player's
// arrives by email, the bot's comes from `balance_probe.dart --journal=` — so
// one tool reads both without special-casing either.
//
//   dart run tool/balance_probe.dart --charters=a_full_purse,poor_soil \
//       --journal=/tmp/bot.pa1
//   dart run tool/calibrate.dart tool/reference_runs/human-*.pa1 /tmp/bot.pa1
//
// MATCHING THE WIN DAY IS NOT THE GOAL. A bot that wins on day 93 by hoarding
// coin and building nothing is still useless for tuning, because a balance
// change would land on it differently than on a player. The curve is the thing:
// population, coin and buildings at matched days.
//
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:ports_ahoy/sim/run_code.dart';

final _code = RegExp(r'PA1~[A-Za-z0-9._~-]+');

DecodedRun _load(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    stderr.writeln('No such file: $path');
    exit(1);
  }
  final m = _code.firstMatch(f.readAsStringSync());
  if (m == null) {
    stderr.writeln('No PA1 run code in $path');
    exit(1);
  }
  return RunCode.decode(m.group(0)!);
}

/// The value on [day], or the last recorded value before it.
///
/// Runs end on different days, so at any checkpoint past a run's end the honest
/// comparison is against how it finished rather than against nothing.
T? _at<T>(DecodedRun r, int day, T Function(dynamic) pick) {
  dynamic best;
  for (final d in r.days) {
    if (d.day <= day) best = d;
  }
  return best == null ? null : pick(best);
}

int? _firstMarkDay(DecodedRun r, String kind) {
  for (final m in r.marks) {
    if (m.kind == kind) return m.day;
  }
  return null;
}

String _pct(num a, num b) {
  if (b == 0) return a == 0 ? '—' : '∞';
  final ratio = a / b;
  return '${(ratio * 100).round()}%';
}

void main(List<String> args) {
  if (args.length != 2) {
    print('usage: dart run tool/calibrate.dart <human.pa1> <bot.pa1>');
    exit(2);
  }
  final human = _load(args[0]);
  final bot = _load(args[1]);

  final humanWin = _firstMarkDay(human, 'win') ?? human.days.length;
  final botWin = _firstMarkDay(bot, 'win') ?? bot.days.length;

  print('reference : ${human.charters.join(", ")}  difficulty ${human.difficulty}'
      '  ${human.won ? "won day $humanWin" : "unfinished"}');
  print('bot       : ${bot.charters.join(", ")}  difficulty ${bot.difficulty}'
      '  ${bot.won ? "won day $botWin" : "unfinished"}');

  if (human.charters.join(',') != bot.charters.join(',') ||
      human.difficulty != bot.difficulty) {
    // Comparing across different charters would produce a confident and
    // completely meaningless number.
    print('\n!!! DIFFERENT CONDITIONS — these two runs are not comparable.');
  }
  if (human.unattendedDays > 0) {
    print('\nnote: ${human.unattendedDays} of the reference run\'s days ran in the '
        'background. The bot plays every day actively, so that much of this '
        'comparison is against nobody.');
  }

  print('\nwin day   human $humanWin   bot $botWin   '
      'bot is ${botWin - humanWin >= 0 ? "+" : ""}${botWin - humanWin} days');

  print('\n${"day".padLeft(5)}  ${"pop h/b".padRight(14)}'
      '${"coin h/b".padRight(22)}${"built h/b".padRight(14)}staffed h/b');
  final checkpoints = [10, 25, 50, 75, 100, math.max(humanWin, botWin)];
  for (final day in checkpoints) {
    final hp = _at<int>(human, day, (d) => d.population);
    final bp = _at<int>(bot, day, (d) => d.population);
    if (hp == null && bp == null) continue;
    final hc = _at<int>(human, day, (d) => d.coin) ?? 0;
    final bc = _at<int>(bot, day, (d) => d.coin) ?? 0;
    final hb = _at<int>(human, day, (d) => d.buildings) ?? 0;
    final bb = _at<int>(bot, day, (d) => d.buildings) ?? 0;
    final hs = _at<int>(human, day, (d) => d.staffed) ?? 0;
    final bs = _at<int>(bot, day, (d) => d.staffed) ?? 0;
    print('${day.toString().padLeft(5)}  '
        '${"${hp ?? 0}/${bp ?? 0}".padRight(6)}${_pct(bp ?? 0, hp ?? 0).padRight(8)}'
        '${"$hc/$bc".padRight(14)}${_pct(bc, hc).padRight(8)}'
        '${"$hb/$bb".padRight(6)}${_pct(bb, hb).padRight(8)}'
        '$hs/$bs');
  }

  // The milestones the bot has been provably wrong about before.
  print('');
  for (final kind in ['hire', 'voyage', 'build']) {
    final h = _firstMarkDay(human, kind);
    final b = _firstMarkDay(bot, kind);
    final label = {'hire': 'first hire', 'voyage': 'first sail', 'build': 'first build'}[kind]!;
    print('${label.padRight(12)} human ${h ?? "never"}   bot ${b ?? "never"}');
  }
  print('${"hires made".padRight(12)} human ${human.marks.where((m) => m.kind == "hire").length}'
      '   bot ${bot.marks.where((m) => m.kind == "hire").length}');
  print('${"sails made".padRight(12)} human ${human.marks.where((m) => m.kind == "voyage").length}'
      '   bot ${bot.marks.where((m) => m.kind == "voyage").length}');

  // One number to watch move. Mean absolute percentage error on the three
  // curves that matter, over the reference run's own length — so a bot that is
  // merely slower does not get flattered by being compared past the finish.
  var n = 0;
  var errPop = 0.0, errCoin = 0.0, errBuilt = 0.0;
  for (final d in human.days) {
    final bp = _at<int>(bot, d.day, (x) => x.population);
    if (bp == null) continue;
    final bc = _at<int>(bot, d.day, (x) => x.coin) ?? 0;
    final bb = _at<int>(bot, d.day, (x) => x.buildings) ?? 0;
    if (d.population > 0) errPop += ((bp - d.population) / d.population).abs();
    if (d.coin > 0) errCoin += ((bc - d.coin) / d.coin).abs();
    if (d.buildings > 0) errBuilt += ((bb - d.buildings) / d.buildings).abs();
    n++;
  }
  if (n > 0) {
    print('\nmean absolute error over the reference run\'s $n days');
    print('  population  ${(errPop / n * 100).toStringAsFixed(1)}%');
    print('  coin        ${(errCoin / n * 100).toStringAsFixed(1)}%');
    print('  buildings   ${(errBuilt / n * 100).toStringAsFixed(1)}%');
    print('  combined    ${((errPop + errCoin + errBuilt) / (3 * n) * 100).toStringAsFixed(1)}%'
        '   <- the number to drive down');
  }
}
