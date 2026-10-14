/// What the game says about growing sheds and the reeve who speeds them.
///
/// Plain functions over the state, so the shed bubble and the reeve's card
/// read the same sums and say the same thing — and so a test can check the
/// wording without tapping a shed on the map.
library;

import '../sim/buildings.dart';
import '../sim/game_state.dart';
import '../sim/retinue.dart';

String _days(int n) => n == 1 ? '1 day' : '$n days';

/// The growth line on a ripening shed's bubble. Null for one that does not
/// ripen.
String? shedGrowthLine(GameState s, Building b) {
  if (!b.def.ripens) return null;
  final pct = (b.maturity * 100).round();
  final left = s.ripenDaysLeft(b).ceil();
  final unaided = s.ripenDaysLeft(b, 1.0).ceil();
  final isGrange = b.defId == 'grange';
  final gain = ((s.grangeYieldBonus - 1) * 100).round();
  final cap = (Balance.grangeMaxYield * 100).round();
  // Named, because a speed-up nobody can see is a speed-up nobody believes in.
  final saved = unaided - left;
  final reeve = saved >= 1 ? ' — ${_days(saved)} sooner for your reeve' : '';

  if (b.workers == 0) {
    return 'Idle — nothing comes on while nobody works it. $pct% grown.';
  }
  if (pct >= 100) {
    return isGrange
        ? 'Fully grown. +$gain% to every shed.'
        : 'Fully grown, and yielding its best.';
  }
  if (isGrange) {
    return '$pct% grown — +$gain% to every shed now, '
        'rising to +$cap% in about ${_days(left)}$reeve.';
  }
  return '$pct% grown — ${(b.ripeness * 100).round()}% of its full yield, '
      'and full in about ${_days(left)}$reeve.';
}

/// What the reeve you keep is doing, right now, on his card: how far he has
/// the land in order, and what he is saving on anything still growing.
List<String> reeveAtWorkLines(GameState s, Retainer hired) {
  final full = (hired.yieldBonus * 100).round();
  final now = ((s.reeveYieldBonus - 1) * 100).round();
  final daysToFull =
      ((1 - s.reeveService) * Balance.reeveServiceDays).ceil();
  final eats = hired.appetite.round();
  final lines = <String>[
    if (s.reeveHungry)
      'Hungry — the stores cannot feed him, so he does nothing until they '
          'can. He eats like $eats villagers.'
    else if (s.reeveService >= 1)
      'The land is in order: every shed +$full%. He eats like $eats '
          'villagers.'
    else
      'Getting the land in order: every shed +$now% now, +$full% in about '
          '${_days(daysToFull)}. Pay him off and that goes with him. He eats '
          'like $eats villagers.',
  ];
  // A run that built a grange before it was retired gets the better of the
  // two, never both, and should be told which is in force.
  final grange = ((s.grangeYieldBonus - 1) * 100).round();
  if (grange >= now && grange > 0) {
    lines.add('Your grange already gives +$grange%; he adds to that only once '
        'his own bonus passes it.');
  }
  final growing = s.growingSheds.length;
  if (growing > 0) {
    final days = s.reeveSavingDays(hired.ripenSpeed).round();
    lines.add('Saving about ${_days(days)} across '
        '${growing == 1 ? "the shed" : "the $growing sheds"} growing now.');
  }
  return lines;
}

/// What the next reeve would do, before you pay: the bonus he works up to,
/// and what he would save on anything growing now — the numbers the hire
/// turns on.
String reeveOfferLine(GameState s, Retainer next) {
  final current = s.hiredOn(RetinueTrack.reeve);
  final bonus = (next.yieldBonus * 100).round();
  final eats = next.appetite.round();
  final head = current == null
      ? 'Every shed +$bonus% over ${Balance.reeveServiceDays.round()} days '
          'of service, eating like $eats villagers'
      : 'Raises every shed to +$bonus%, keeping the order he has made, '
          'and eats like $eats villagers';
  if (s.growingSheds.isEmpty) return '$head.';
  final more = (s.reeveSavingDays(next.ripenSpeed) -
          s.reeveSavingDays(s.reeveSpeed))
      .round();
  return more >= 1
      ? '$head, and about ${_days(more)} off what is growing now.'
      : '$head.';
}
