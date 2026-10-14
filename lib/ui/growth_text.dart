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

/// What the reeve you keep is doing, right now, on his card.
String reeveAtWorkLine(GameState s, Retainer hired) {
  final growing = s.growingSheds.length;
  if (growing == 0) {
    return 'Nothing is growing, so he has nothing to bring on until you raise '
        'another shed that ripens.';
  }
  final days = s.reeveSavingDays(hired.ripenSpeed).round();
  return 'Saving about ${_days(days)} across '
      '${growing == 1 ? "the shed" : "the $growing sheds"} growing now.';
}

/// What the next reeve would do for what is growing now, before you pay.
/// That is the number the hire turns on, and it is worth a lot more early.
String reeveOfferLine(GameState s, Retainer next) {
  final now = s.reeveSpeed;
  final more = s.reeveSavingDays(next.ripenSpeed) - s.reeveSavingDays(now);
  if (s.growingSheds.isEmpty) {
    return 'Nothing is growing now, so he would only help sheds you raise from '
        'here on.';
  }
  final days = more.round();
  return now > 1
      ? 'Would save about ${_days(days)} more on what is growing now.'
      : 'Would save about ${_days(days)} on what is growing now.';
}
