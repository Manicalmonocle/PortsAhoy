import '../sim/game_state.dart';
import '../sim/resources.dart';

/// Contextual nudges rather than a scripted tutorial.
///
/// A hint fires the moment its situation is actually true, says one thing, and
/// never comes back once dismissed. Nothing is gated behind them and nothing
/// blocks play — a player who dismisses every one has lost no content.
class HintDef {
  const HintDef({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
  });

  final String id;
  final String title;
  final String body;

  /// True when this hint has something useful to say right now.
  final bool Function(GameState s) when;
}

/// Ordered by priority — the first match is the one shown.
final List<HintDef> kHints = [
  HintDef(
    id: 'welcome',
    title: 'You have the post',
    body: 'Hands are your scarcest thing. Post them to sheds in the harbour '
        'below; every hand eats each day and draws a wage whether or not it '
        'is working. Tap a shed to staff it.',
    when: (s) => s.day <= 2,
  ),
  HintDef(
    id: 'sell_first',
    title: 'A ship is at the quay',
    body: 'Ships buy what you have and sell what you lack. Selling in bulk '
        'drives that price down for days, so spread your trade around rather '
        'than dumping everything on one captain.',
    when: (s) => s.market.ships.isNotEmpty && s.day >= 2,
  ),
  HintDef(
    id: 'idle_hands',
    title: 'Idle hands',
    body: 'Some of your people are not posted to anything. They still eat and '
        'still draw wages. Put them to work, or you are paying for nothing.',
    when: (s) => s.idleWorkers >= 2 && s.day >= 3,
  ),
  HintDef(
    id: 'starved',
    title: 'A shed has nothing to work with',
    body: 'A workshop runs at the rate of its scarcest input. If the sawmill '
        'has no timber, staffing it harder changes nothing — staff the forest '
        'camp that feeds it instead.',
    when: (s) => s.buildings.any((b) =>
        b.workers > 0 && b.def.isWorkshop && b.lastEfficiency < 0.5),
  ),
  HintDef(
    id: 'yard_full',
    title: 'A shed has filled its yard',
    body: 'Sheds stack what they make in their own yard and wait for you. A '
        'full yard stops the shed — nothing is lost, but nothing more is being '
        'made. Tap it to collect, or build a warehouse: each one makes every '
        'yard half again as big.',
    when: (s) => s.buildings.any((b) => b.holdFullness >= 0.999),
  ),
  HintDef(
    id: 'unlocks',
    title: 'The port grows into it',
    body: 'You cannot build everything yet. The Build panel lists what is '
        'still to come and the one thing that unlocks each — usually just '
        'raising the shed before it.',
    when: (s) => s.day >= 2,
  ),
  HintDef(
    id: 'full_shed',
    title: 'A store is full',
    body: 'A full shed stops producing entirely. Sell it down, or build a '
        'warehouse. This is also the only thing that limits you while the app '
        'is closed — there is nothing to buy that raises it.',
    when: (s) => Resource.values
        .any((r) => !r.isContraband && s.stock[r] >= s.storageCapacity - 1),
  ),
  HintDef(
    id: 'refine',
    title: 'Refining beats selling raw',
    body: 'Raw timber pays 0.6c per worker-hour. Sawn into planks it pays '
        'nearly twice that, and the deeper chains pay better still. Every '
        'shed shows its rate on the Build tab.',
    when: (s) => s.day >= 6 && s.buildings.every((b) => !b.def.isWorkshop),
  ),
  HintDef(
    id: 'flax',
    title: 'The flax problem',
    body: 'The ropewalk and the weaver both eat flax. The weaver pays more per '
        'worker; the ropewalk gets more out of each stalk. Which one you staff '
        'depends on whether hands or flax is your bottleneck today.',
    when: (s) =>
        s.buildings.any((b) => b.defId == 'ropewalk') &&
        s.buildings.any((b) => b.defId == 'weaver'),
  ),
  HintDef(
    id: 'coin_idle',
    title: 'Coin is only worth what it buys',
    body: 'You are holding more coin than you need. An Import Berth spends it '
        'by the hour on raw cargo — it is a rate you staff, not a shop. It '
        'only ever lands raws, so the finished goods still have to come out of '
        'your own sheds.',
    when: (s) =>
        s.coin > 4000 && !s.buildings.any((b) => b.def.imports),
  ),
  HintDef(
    id: 'hire',
    title: 'You can put people on the payroll',
    body: 'Under Trade there are captains, merchants and quartermasters for '
        'hire. A merchant raises every price you are paid; a captain makes '
        'voyages faster and safer; a quartermaster carts your yards in for '
        'you. They cost coin to sign and a wage every day.',
    when: (s) => s.coin >= 1600 && s.captainLevel == 0 && s.merchantLevel == 0,
  ),
  HintDef(
    id: 'voyages',
    title: 'Send your own cargo out',
    body: 'Selling on your own quay drives the price down. A voyage does not '
        'touch your local market at all — and each port pays for different '
        'things. The Trade panel shows which one pays best per day for '
        'whatever you have loaded.',
    when: (s) => s.day >= 10 && s.voyages.isEmpty,
  ),
  HintDef(
    id: 'omen',
    title: 'That was a warning',
    body: 'Omens tell you exactly what is coming and for how long, and they do '
        'not lie. Use the time — stockpile, or move hands off whatever is '
        'about to stop working.',
    when: (s) => s.events.omens(s.tick).isNotEmpty,
  ),
  HintDef(
    id: 'winter',
    title: 'Winter is a season, not an accident',
    body: 'The sound freezes in winter and nothing reaches the quay. It is the '
        'heaviest event in the deck and it happens every year, so it is worth '
        'building a stockpile before it arrives.',
    when: (s) => s.day >= 75,
  ),
  HintDef(
    id: 'growth',
    title: 'Why the town is not growing',
    body: 'People move in only when three things are true: a roof is free, '
        'there are two days of food in store, and the payroll is covered. '
        'Unpaid hands leave again, which is why a port can sit at the same '
        'number for days. Whichever one is missing is named under the HUD.',
    when: (s) => s.growthIsStalled && s.day >= 6,
  ),
  HintDef(
    id: 'hungry',
    title: 'The stores are running down',
    body: 'Every person eats one unit a day, fish first, then grain. Run out '
        'and a family leaves on the evening tide. Staff a farm or a wharf.',
    when: (s) => s.foodDays < 4,
  ),
  HintDef(
    id: 'dark_trade',
    title: 'You are in the dark trade now',
    body: 'Free traders will now call. They buy contraband and will swap it '
        'for materials at a rate coin cannot match. Everything you hold in '
        'plain sight is noticed — post hands to a bonded cellar to hide it.',
    when: (s) => s.darkTradeOpen,
  ),
  HintDef(
    id: 'cutter',
    title: 'A revenue cutter is standing by',
    body: 'Only what is exposed can be taken; concealed stock is safe, and no '
        'legitimate good is ever touched. You can scuttle it or declare it — '
        'both are free. Pausing costs nothing, so take your time.',
    when: (s) => s.cutterOnStation,
  ),
];

/// The one hint worth showing right now, if any.
HintDef? nextHint(GameState state, Set<String> dismissed) {
  for (final h in kHints) {
    if (dismissed.contains(h.id)) continue;
    if (h.when(state)) return h;
  }
  return null;
}
