import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/sound_board.dart';
import '../game_controller.dart';
import '../sim/market.dart';
import '../sim/resources.dart';
import '../sim/retinue.dart';
import 'pet_panel.dart';
import 'theme.dart';

class MarketTab extends StatefulWidget {
  const MarketTab({super.key, required this.controller});

  final GameController controller;

  /// How long the quay holds still after the player last touched it.
  static const Duration hold = Duration(milliseconds: 2500);

  /// The wall clock the hold is measured on. A test sets its own.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  @override
  State<MarketTab> createState() => _MarketTabState();
}

/// THE QUAY HOLDS STILL WHILE YOU TRADE.
///
/// Reported from play: "screens jump around at every tick making buying /
/// selling aggravating". Measured by stepping a port one tick at a time with
/// nothing touched, the quay moved under the player's thumb three ways:
///
///  - a ship that sailed took its card with it, and every card below slid up
///    by a whole card — 173 to 345 pixels — so the button under the thumb
///    belonged to another ship. Ships are listed oldest first, and the oldest
///    is always the next to sail, so this happened at every departure;
///  - an offer filled — by the player's own tap on "All", as often as not —
///    vanished, and every row below slid up 57 pixels;
///  - a ship's name wrapped onto a second line whenever its "sails in" pill
///    turned bold at ten hours out, and unwrapped at nine (see _ShipCard).
///
/// So while the player has touched the quay in the last [MarketTab.hold], it
/// keeps what it was showing: a ship that has sailed stays where it was, dimmed
/// and marked as sailed; a row that has filled stays, dimmed; a ship that
/// arrives joins at the bottom, below anything being read. Nothing on it can
/// be acted on once it is gone. When the player lets go, it catches up in one
/// move, while nobody is aiming at it.
class _MarketTabState extends State<MarketTab> {
  DateTime _lastTouch = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _release;

  /// The ships on screen, in the order they are on screen.
  List<Ship> _shown = [];

  /// The rows each ship was showing when the hold began — its offers, wares
  /// and barters, and the ship itself standing for its prize row.
  final Map<Ship, Set<Object>> _rows = {};

  bool _cutter = false;

  bool get _holding => MarketTab.now().difference(_lastTouch) < MarketTab.hold;

  void _touched(PointerEvent _) {
    _lastTouch = MarketTab.now();
    _release?.cancel();
    // Catch up once the hold lapses, even if nothing else rebuilds the quay —
    // a paused port does not tick.
    _release = Timer(MarketTab.hold, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _release?.cancel();
    super.dispose();
  }

  static Set<Object> _onScreen(Ship s) => {
    ...s.offers.where((o) => !o.isFilled),
    ...s.wares.where((w) => !w.isFilled),
    ...s.barters.where((b) => !b.taken),
    if (s.foreign && s.prizeTons > 0) s,
  };

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state;
    final live = state.market.ships;

    if (!_holding) {
      _shown = List.of(live);
      _rows
        ..clear()
        ..addEntries(live.map((s) => MapEntry(s, _onScreen(s))));
      _cutter = state.cutterOnStation;
    } else {
      // Newcomers join at the bottom, below anything being read.
      for (final s in live) {
        if (!_shown.contains(s)) {
          _shown.add(s);
          _rows[s] = _onScreen(s);
        }
      }
    }

    return Listener(
      onPointerDown: _touched,
      onPointerMove: _touched,
      onPointerSignal: _touched,
      onPointerPanZoomStart: _touched,
      onPointerPanZoomUpdate: _touched,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_cutter) _CutterCard(controller: controller),
          // SHE IS A SHIP, SO SHE BELONGS WHERE THE SHIPS ARE. The offer card
          // was first put under Trade, beside the pet it would become, which
          // is where the kept animal lives and NOT where anybody looks for a
          // hull. A player kept her waiting and then could not find her again:
          // "I clicked to make the ship wait but then I couldn't find it again
          // once I got the coin." Pinned above the market, like the cutter,
          // because neither of them is something you trade with.
          PetOfferCard(controller: controller),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              'Selling in bulk drives a price down for days; buying pushes it '
              'up. Spread your trade.',
              style: TextStyle(fontSize: 11, color: Palette.fog, height: 1.4),
            ),
          ),
          if (_shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No ships at the quay.\nAnother is always on the tide.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.fog, height: 1.5),
              ),
            ),
          ..._shown.map(
            (s) => _ShipCard(
              controller: controller,
              ship: s,
              sailed: !live.contains(s),
              rows: _rows[s] ?? _onScreen(s),
            ),
          ),
        ],
      ),
    );
  }
}

/// The revenue cutter, pinned above everything else.
///
/// It shows the one number that decides the outcome — exposed units — plus
/// both free ways out. Neither costs coin, and nothing in the game shortens
/// the window in either direction.
class _CutterCard extends StatelessWidget {
  const _CutterCard({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final hours = state.cutterInspectTick - state.tick;
    final exposed = state.exposedUnits;
    final clean = exposed <= 1e-6;

    return Card(
      color: (clean ? Palette.moss : Palette.rust).withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: clean ? Palette.moss : Palette.rust),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('⚓', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${state.cutterName()} boards in ${hours}h',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: clean ? Palette.moss : Palette.rust),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              clean
                  ? 'Nothing is in plain sight. They will find salt fish and '
                      'leave you better thought of than before.'
                  : '${fmt(exposed)} units are in plain sight and will be '
                      'seized. Concealed stock is safe.',
              style: const TextStyle(
                  fontSize: 11, color: Palette.fog, height: 1.4),
            ),
            if (!clean) ...[
              const SizedBox(height: 10),
              for (final r in Resource.contraband)
                if (state.exposedShareOf(r) > 0.5)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Text(r.icon, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${fmt(state.exposedShareOf(r))} ${r.label.toLowerCase()} exposed',
                            style: const TextStyle(
                                fontSize: 11, color: Palette.fog),
                          ),
                        ),
                        _SellButton(
                          label: 'Declare',
                          enabled: true,
                          onTap: () => controller.act((s) =>
                              s.declareToCustoms(r, s.exposedShareOf(r))),
                        ),
                        const SizedBox(width: 6),
                        _SellButton(
                          label: 'Scuttle',
                          enabled: true,
                          onTap: () => controller
                              .act((s) => s.scuttle(r, s.exposedShareOf(r))),
                        ),
                      ],
                    ),
                  ),
              Text(
                'Declaring sells to the Crown at a poor price. Scuttling puts '
                'it over the side for nothing. Both are free, and neither '
                'changes how closely you are watched.',
                style: TextStyle(
                    fontSize: 10,
                    color: Palette.fog.withValues(alpha: 0.75),
                    height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShipCard extends StatelessWidget {
  const _ShipCard({
    required this.controller,
    required this.ship,
    required this.sailed,
    required this.rows,
  });

  final GameController controller;
  final Ship ship;

  /// Gone from the quay, but kept in place while the player is trading.
  final bool sailed;

  /// The rows to show: what was on screen when the hold began.
  final Set<Object> rows;

  /// A row kept after it has gone, dimmed so it reads as done.
  static Widget _dim(bool live, Widget row) =>
      live ? row : Opacity(opacity: 0.4, child: row);

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final hoursLeft = ship.departTick - state.tick;
    final leavingSoon = hoursLeft <= 10;
    // In the order the ship lists them, as they were on screen; a row that
    // has filled since stays, dimmed, rather than closing up under a thumb.
    final buying = ship.offers.where(rows.contains).toList();
    final selling = ship.wares.where(rows.contains).toList();
    final swaps = ship.barters.where(rows.contains).toList();

    return Opacity(
      opacity: sailed ? 0.55 : 1,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    ship.isFreeTrader ? '🏴' : '⛴️',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ONE LINE, ALWAYS. It wrapped whenever the pill beside
                        // it widened — the pill turns bold at ten hours out and
                        // has two digits until nine — so the whole quay lurched
                        // a line at ten hours and back again at nine.
                        Text(
                          ship.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          ship.isFreeTrader
                              ? 'Free trader — asks no questions'
                              : 'Crown trader',
                          style: TextStyle(
                            fontSize: 10,
                            color: ship.isFreeTrader
                                ? Palette.lamp
                                : Palette.fog.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // A fixed width, so neither the bold of "leaving soon" nor a
                  // second digit can move anything else on the card.
                  Container(
                    width: 88,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: sailed
                          ? Palette.deep
                          : leavingSoon
                          ? Palette.rust.withValues(alpha: 0.2)
                          : Palette.deep,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        sailed ? 'has sailed' : 'sails in ${hoursLeft}h',
                        style: TextStyle(
                          fontSize: 11,
                          color: sailed
                              ? Palette.fog
                              : leavingSoon
                              ? Palette.rust
                              : Palette.fog,
                          fontWeight: leavingSoon && !sailed
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (buying.isNotEmpty) ...[
                const _RowLabel('Wants to buy'),
                ...buying.map(
                  (o) => _dim(
                    !sailed && !o.isFilled,
                    _OfferRow(
                      controller: controller,
                      ship: ship,
                      offer: o,
                      live: !sailed && !o.isFilled,
                    ),
                  ),
                ),
              ],
              if (selling.isNotEmpty) ...[
                const _RowLabel('Has for sale'),
                ...selling.map(
                  (w) => _dim(
                    !sailed && !w.isFilled,
                    _WareRow(
                      controller: controller,
                      ship: ship,
                      ware: w,
                      live: !sailed && !w.isFilled,
                    ),
                  ),
                ),
              ],
              if (swaps.isNotEmpty) ...[
                const _RowLabel('Will trade, no coin'),
                ...swaps.map(
                  (b) => _dim(
                    !sailed && !b.taken,
                    _BarterRow(
                      controller: controller,
                      ship: ship,
                      deal: b,
                      live: !sailed && !b.taken,
                    ),
                  ),
                ),
              ],
              if (rows.contains(ship))
                _PrizeRow(
                  controller: controller,
                  ship: ship,
                  live: !sailed && ship.prizeTons > 0,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: Palette.fog.withValues(alpha: 0.6),
          ),
        ),
      );
}

/// Cargo the captain will part with, at a markup over the going rate.
class _WareRow extends StatelessWidget {
  const _WareRow({
    this.live = true,
    required this.controller,
    required this.ship,
    required this.ware,
  });

  final GameController controller;
  final Ship ship;
  final Offer ware;

  /// False for a row kept on screen after it has gone — filled, taken, or on a
  /// ship that has sailed — while the quay holds still. Dimmed, and nothing
  /// on it can be pressed.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final max = state.maxPurchasable(ware);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(ware.resource.icon, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        ware.resource.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${ware.pricePerUnit.toStringAsFixed(2)}c',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Palette.sea,
                      ),
                    ),
                  ],
                ),
                _OneLine(
                  'offers ${ware.quantity.round()} · you can take ${max.floor()}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Palette.fog.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          _SellButton(
            label: 'Buy 10',
            enabled: live && max >= 10,
            onTap: () {
              controller.act((s) => s.buy(ship, ware, 10));
              SoundBoard.instance.play(Sfx.coins);
            },
          ),
          const SizedBox(width: 6),
          _SellButton(
            label: 'Max',
            enabled: live && max >= 1,
            onTap: () {
              controller.act((s) => s.buy(ship, ware, max));
              SoundBoard.instance.play(Sfx.coins);
            },
          ),
        ],
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({
    this.live = true,
    required this.controller,
    required this.ship,
    required this.offer,
  });

  final GameController controller;
  final Ship ship;
  final Offer offer;

  /// False for a row kept on screen after it has gone — filled, taken, or on a
  /// ship that has sailed — while the quay holds still. Dimmed, and nothing
  /// on it can be pressed.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final held = state.stock[offer.resource];
    final sellable = held < offer.quantity ? held : offer.quantity;
    final canSell = sellable >= 1.0;

    // Is this captain paying above or below the going rate?
    final market = state.market.priceOf(offer.resource);
    final premium = market > 0 ? (offer.pricePerUnit / market - 1) * 100 : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(offer.resource.icon, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        offer.resource.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${offer.pricePerUnit.toStringAsFixed(2)}c',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Palette.brass,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      premium >= 0
                          ? '+${premium.round()}%'
                          : '${premium.round()}%',
                      style: TextStyle(
                        fontSize: 10,
                        color: premium >= 0 ? Palette.moss : Palette.rust,
                      ),
                    ),
                  ],
                ),
                _OneLine(
                  'wants ${offer.quantity.round()} · you hold ${fmt(held)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Palette.fog.withValues(alpha: 0.8),
                  ),
                ),
                // What your factor is doing to this bid. The badge above is
                // the market's premium over the going rate and has nothing to
                // do with them — which is precisely what got misread as the
                // merchant's work.
                if (state.hiredOn(RetinueTrack.merchant) != null)
                  Builder(
                    builder: (_) {
                      final m = state.hiredOn(RetinueTrack.merchant)!;
                      final net = state.quayNetPerUnit(offer);
                      final up = net >= offer.pricePerUnit;
                      return _OneLine(
                        '${m.name}: ${net.toStringAsFixed(2)}c a unit to you '
                        '(+${((m.sellBonus - 1) * 100).round()}% '
                        '−${(m.commission * 100).toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: up ? Palette.moss : Palette.rust,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          _SellButton(
            label: '10',
            enabled: live && held >= 10 && offer.quantity >= 1,
            onTap: () {
              controller.act((s) => s.sell(ship, offer, 10));
              SoundBoard.instance.play(Sfx.coins);
            },
          ),
          const SizedBox(width: 6),
          _SellButton(
            label: 'All',
            primary: true,
            enabled: live && canSell,
            onTap: () {
              controller.act((s) => s.sell(ship, offer, sellable));
              SoundBoard.instance.play(Sfx.coins);
            },
          ),
        ],
      ),
    );
  }
}

/// Contraband straight into materials, with no coin involved.
///
/// The best parity in the game and the loudest thing you can do on a quay.
class _BarterRow extends StatelessWidget {
  const _BarterRow({
    this.live = true,
    required this.controller,
    required this.ship,
    required this.deal,
  });

  final GameController controller;
  final Ship ship;
  final Barter deal;

  /// False for a row kept on screen after it has gone — filled, taken, or on a
  /// ship that has sailed — while the quay holds still. Dimmed, and nothing
  /// on it can be pressed.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final hasGoods = state.stock[deal.give] >= deal.giveQty;
    final room = state.storageCapacity - state.stock[deal.take];
    final hasRoom = room >= deal.takeQty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(deal.give.icon, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward, size: 12, color: Palette.fog),
          const SizedBox(width: 6),
          Text(deal.take.icon, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${deal.giveQty.round()} ${deal.give.label.toLowerCase()} '
                  '→ ${deal.takeQty.round()} ${deal.take.label.toLowerCase()}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  hasGoods
                      ? (hasRoom ? 'raises notoriety' : 'no room in the sheds')
                      : 'you hold ${fmt(state.stock[deal.give])}',
                  style: TextStyle(
                    fontSize: 10,
                    color: hasGoods && hasRoom
                        ? Palette.lamp
                        : Palette.fog.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          _SellButton(
            label: 'Trade',
            primary: true,
            enabled: live && hasGoods && hasRoom,
            onTap: () => controller.act((s) => s.barter(ship, deal)),
          ),
        ],
      ),
    );
  }
}

/// A foreign hull at your quay, and the option to board her.
///
/// Resolves the instant you press it. There is no voyage and nothing to wait
/// for, which is exactly why there is nothing here anyone could sell you.
class _PrizeRow extends StatelessWidget {
  const _PrizeRow({
    required this.controller,
    required this.ship,
    this.live = true,
  });

  final GameController controller;
  final Ship ship;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final blocker = state.prizeBlocker(ship);
    final covered = state.marqueTons >= ship.prizeTons;
    final chance = state.prizeSuccessChance(ship);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Palette.deep,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: covered ? Palette.brass : Palette.rust.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          const Text('🏴', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Foreign hull · ${ship.prizeTons} tons',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  blocker ??
                      '${(chance * 100).round()}% to carry her · '
                          '${covered ? "covered by your Letter" : "no Letter — this is piracy"}',
                  style: TextStyle(
                    fontSize: 10,
                    color: blocker != null
                        ? Palette.fog.withValues(alpha: 0.8)
                        : (covered ? Palette.moss : Palette.rust),
                  ),
                ),
              ],
            ),
          ),
          _SellButton(
            label: 'Board',
            primary: true,
            enabled: live && blocker == null,
            onTap: () => controller.act((s) => s.takePrize(ship)),
          ),
        ],
      ),
    );
  }
}

class _SellButton extends StatelessWidget {
  const _SellButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: primary
          ? FilledButton(
              onPressed: enabled ? onTap : null,
              style: FilledButton.styleFrom(
                backgroundColor: Palette.brass,
                foregroundColor: Palette.deep,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: enabled ? onTap : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: Palette.fog,
                side: const BorderSide(color: Palette.line),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(label),
            ),
    );
  }
}
/// A line that stays one line: it shrinks to fit rather than wrapping.
///
/// For text whose numbers change every tick. A wrap that comes and goes as a
/// count gains or loses a digit moves everything below it — the quay's "wants
/// 24 · you hold 0" was already two lines tall on a phone.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text, {required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(text, maxLines: 1, style: style),
  );
}
