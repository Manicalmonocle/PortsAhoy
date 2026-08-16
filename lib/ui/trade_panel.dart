import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../sim/game_state.dart';
import '../sim/resources.dart';
import '../sim/retinue.dart';
import '../sim/trade.dart';
import 'theme.dart';

/// Trade you start.
///
/// The quay is reactive — you answer whoever turns up. This is the other half:
/// buy what you actually need, and send your own cargo somewhere that wants it
/// instead of dumping it locally and watching the price fall.
class TradePanel extends StatefulWidget {
  const TradePanel({super.key, required this.controller});

  final GameController controller;

  @override
  State<TradePanel> createState() => _TradePanelState();
}

class _TradePanelState extends State<TradePanel> {
  String _destId = kDestinations.first.id;
  final Map<Resource, double> _cargo = {};
  bool _escort = false;

  Destination get _dest => destinationById(_destId);

  /// Goods worth loading: anything you actually hold.
  List<Resource> _loadable(GameState s) => Resource.values
      .where((r) => s.stock[r] >= 1 && (!r.isContraband || s.darkTradeOpen))
      .toList();

  /// Trim the loaded hold to what the stores still contain, so the figures on
  /// screen can never promise cargo that has since been eaten or sold.
  void _reconcile(GameState s) {
    for (final r in _cargo.keys.toList()) {
      final have = s.stock[r];
      if (have < 1) {
        _cargo.remove(r);
      } else if (_cargo[r]! > have) {
        _cargo[r] = have;
      }
    }
  }

  void _setCargo(Resource r, double qty) {
    setState(() {
      if (qty <= 0) {
        _cargo.remove(r);
      } else {
        _cargo[r] = qty;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final s = controller.state;
    _reconcile(s);
    final quote = s.quoteVoyage(_dest, _cargo);
    final units = _cargo.values.fold(0.0, (a, b) => a + b);
    final bestQuote = kDestinations
        .map((d) => s.quoteVoyage(d, _cargo))
        .fold(0, (a, b) => a > b ? a : b);
    final canSend = s.canSendVoyage && units >= 1;

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        // ---- Who works for you --------------------------------------------
        _Label('Your people · ${s.officersRetained}/${s.officerCapacity} '
            'berths'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            s.officerCapacity >= 3
                ? 'A harbour this size keeps all three on the books.'
                : 'A port this size supports ${s.officerCapacity} '
                    'officer${s.officerCapacity == 1 ? "" : "s"}. '
                    'Another berth opens at '
                    '${s.producingSheds < 9 ? 9 : 16} working sheds.',
            style: const TextStyle(
                fontSize: 11, color: Palette.fog, height: 1.4),
          ),
        ),
        _RetinueCard(controller: controller, track: RetinueTrack.captain),
        _RetinueCard(controller: controller, track: RetinueTrack.merchant),
        _RetinueCard(
            controller: controller, track: RetinueTrack.quartermaster),

        // ---- At sea -------------------------------------------------------
        if (s.voyages.isNotEmpty) ...[
          const _Label('At sea'),
          ...s.voyages.map((v) => _VoyageCard(state: s, voyage: v)),
        ],

        // ---- Send a consignment -------------------------------------------
        const _Label('Send a consignment'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kDestinations.map((d) {
                    final on = d.id == _destId;
                    // The quote for the cargo you have actually loaded, and
                    // what it works out at per day — which is the comparison
                    // that decides where a hull goes.
                    final q = s.quoteVoyage(d, _cargo);
                    final perDay = d.days > 0 ? q / d.days : 0;
                    return GestureDetector(
                      onTap: () => setState(() => _destId = d.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: on
                              ? Palette.brass.withValues(alpha: 0.20)
                              : Palette.deep,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: on ? Palette.brass : Palette.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        on ? Palette.brass : Palette.fog)),
                            Text('${d.days}d · ${(d.risk * 100).round()}% risk',
                                style: const TextStyle(
                                    fontSize: 10, color: Palette.fog)),
                            if (units >= 1)
                              Text(
                                '${q}c · ${perDay.round()}c/day',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: q == bestQuote
                                      ? Palette.moss
                                      : Palette.fog,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Text(_dest.blurb,
                    style: const TextStyle(
                        fontSize: 11, color: Palette.fog, height: 1.4)),
                const SizedBox(height: 6),
                Text(
                  'Pays well for: ${_dest.wants.entries.where((e) => e.value > 1).map((e) => e.key.label.toLowerCase()).join(", ")}',
                  style: const TextStyle(fontSize: 11, color: Palette.moss),
                ),
              ],
            ),
          ),
        ),

        const _Label('Load the hold'),
        if (_loadable(s).isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Nothing in the stores to load yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.fog)),
          ),
        ..._loadable(s).map((r) {
          final best = kDestinations
              .reduce((a, b) => a.dailyRateFor(r) >= b.dailyRateFor(r) ? a : b);
          return _CargoRow(
            resource: r,
            held: s.stock[r],
            loaded: _cargo[r] ?? 0,
            pays: _dest.payFor(r),
            bestPort: best.id == _destId ? null : best.name,
            onChanged: (v) => _setCargo(r, v),
          );
        }),

        // ---- Dispatch ------------------------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${units.round()} units → ${_dest.name}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          Text(
                            'Quoted ${quote}c, back on day '
                            '${s.day + _dest.days}',
                            style: const TextStyle(
                                fontSize: 11, color: Palette.brass),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: canSend
                          ? () {
                              var sent = false;
                              controller.act((g) => sent = g.sendVoyage(
                                  _dest, Map.of(_cargo),
                                  escorted: _escort));
                              // Only clear the hold if she actually sailed;
                              // wiping it on a refusal is what made a failed
                              // send look like a successful one.
                              if (sent) {
                                setState(_cargo.clear);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Palette.panel,
                                    content: Text(
                                      'She could not sail — the stores no '
                                      'longer hold that cargo.',
                                      style: TextStyle(color: Palette.fog),
                                    ),
                                  ),
                                );
                              }
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Palette.brass,
                        foregroundColor: Palette.deep,
                      ),
                      child: const Text('Send'),
                    ),
                  ],
                ),
                if (s.stock[Resource.powder] >= Balance.escortPowderCost)
                  CheckboxListTile(
                    value: _escort,
                    onChanged: (v) => setState(() => _escort = v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Sail escorted — ${Balance.escortPowderCost.round()} powder, halves the risk',
                      style: const TextStyle(
                          fontSize: 11, color: Palette.fog),
                    ),
                  ),
                if (!s.canSendVoyage)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Every hull you have is already at sea.',
                      style: TextStyle(fontSize: 11, color: Palette.rust),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ---- The chandler --------------------------------------------------
        const _Label('The chandler'),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Text(
            'Sells raw stock and food on demand, at a premium over the going '
            'rate. Finished goods are not for sale at any price — those come '
            'out of your own sheds.',
            style: TextStyle(fontSize: 11, color: Palette.fog, height: 1.4),
          ),
        ),
        ...Balance.chandlerStock.map((r) => _ChandlerRow(
              controller: controller,
              resource: r,
            )),
      ],
    );
  }
}

/// One hiring track: who you have, what they do, and who is next.
class _RetinueCard extends StatelessWidget {
  const _RetinueCard({required this.controller, required this.track});

  final GameController controller;
  final RetinueTrack track;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final hired = s.hiredOn(track);
    final next = s.nextOn(track);

    final (icon, label) = switch (track) {
      RetinueTrack.captain => ('🧭', 'Captain'),
      RetinueTrack.merchant => ('⚖️', 'Merchant'),
      RetinueTrack.quartermaster => ('📋', 'Quartermaster'),
    };

    String effectOf(Retainer r) => switch (track) {
          RetinueTrack.captain =>
            'New voyages ${(100 - r.voyageSpeed * 100).round()}% faster, '
                'risk down ${(100 - r.voyageRisk * 100).round()}%',
          RetinueTrack.merchant =>
            'Quay prices +${((r.sellBonus - 1) * 100).round()}%, '
                'voyages +${((r.voyagePay - 1) * 100).round()}%',
          RetinueTrack.quartermaster => switch (r.autoCollect) {
              AutoCollect.everyOtherDay =>
                'Carts the port in every other evening',
              AutoCollect.daily => 'Carts the port in every evening',
              AutoCollect.hourly => 'Carts everything in, every hour',
              AutoCollect.none => '',
            },
        };

    final idle = switch (track) {
      RetinueTrack.captain =>
        'Nobody. Your voyages sail at whatever pace they manage.',
      RetinueTrack.merchant =>
        'Nobody. You take whatever price you are offered.',
      RetinueTrack.quartermaster =>
        'Nobody. Every yard is carted in by hand — yours.',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
                if (hired != null)
                  Text(
                      hired.commission > 0
                          ? '${hired.dailyWage}c/day · '
                              '${(hired.commission * 100).toStringAsFixed(1)}%'
                          : '${hired.dailyWage}c/day',
                      style: const TextStyle(
                          fontSize: 11, color: Palette.rust)),
              ],
            ),
            const SizedBox(height: 6),
            if (hired == null)
              Text(idle,
                  style: const TextStyle(fontSize: 11, color: Palette.fog))
            else ...[
              Text('${hired.name} — ${hired.title}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Palette.brass)),
              const SizedBox(height: 2),
              Text(effectOf(hired),
                  style: const TextStyle(fontSize: 11, color: Palette.moss)),
              if (hired.commission > 0)
                Text(
                    'Takes ${(hired.commission * 100).toStringAsFixed(1)}% of '
                    'every sale ${track == RetinueTrack.captain ? "abroad" : "they handle"}',
                    style: const TextStyle(fontSize: 11, color: Palette.rust)),
            ],
            const SizedBox(height: 10),
            if (next != null)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Next: ${next.name}, ${next.title}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        Text(next.blurb,
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: Palette.fog,
                                height: 1.3)),
                        const SizedBox(height: 2),
                        Text(
                            next.commission > 0
                                ? '${next.coinCost}c to sign · '
                                    '${next.dailyWage}c a day · '
                                    '${(next.commission * 100).toStringAsFixed(1)}% '
                                    'of what they sell'
                                : '${next.coinCost}c to sign · '
                                    '${next.dailyWage}c a day',
                            style: const TextStyle(
                                fontSize: 11, color: Palette.brass)),
                        if (s.producingSheds < next.requiresBuildings)
                          Text(
                            'Needs ${next.requiresBuildings} working sheds '
                            '(you have ${s.producingSheds})',
                            style: const TextStyle(
                                fontSize: 11, color: Palette.lamp),
                          )
                        // A hire blocked purely by berths must say so, or it
                        // reads as a bug rather than a decision.
                        else if (s.levelOn(track) == 0 &&
                            !s.hasFreeOfficerBerth)
                          Text(
                            'No berth free — you keep '
                            '${s.officersRetained} of ${s.officerCapacity} '
                            'officers. Pay one off, or build up to '
                            '${s.producingSheds < 9 ? 9 : 16} sheds.',
                            style: const TextStyle(
                                fontSize: 11, color: Palette.lamp),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: s.canHire(next)
                        ? () => controller.act((g) => g.hire(next))
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Palette.brass,
                      foregroundColor: Palette.deep,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Hire'),
                  ),
                ],
              )
            else
              const Text('Nobody better to be had on this coast.',
                  style: TextStyle(fontSize: 11, color: Palette.fog)),
            if (hired != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => controller.act((g) => g.dismiss(track)),
                  style: TextButton.styleFrom(
                    foregroundColor: Palette.fog,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Pay off', style: TextStyle(fontSize: 11)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
              color: Palette.fog),
        ),
      );
}

class _VoyageCard extends StatelessWidget {
  const _VoyageCard({required this.state, required this.voyage});
  final GameState state;
  final Voyage voyage;

  @override
  Widget build(BuildContext context) {
    final p = voyage.progress(state.tick);
    final hoursLeft = voyage.returnTick - state.tick;
    final daysLeft = (hoursLeft / Balance.ticksPerDay).ceil();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('⛵', style: TextStyle(fontSize: 17)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${voyage.totalCargo.round()} units → ${voyage.destination.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
                if (voyage.escorted)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Text('escorted',
                        style:
                            TextStyle(fontSize: 10, color: Palette.moss)),
                  ),
                Text('${voyage.quotedCoin}c',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Palette.brass)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: p,
                minHeight: 5,
                backgroundColor: Palette.deep,
                valueColor: const AlwaysStoppedAnimation(Palette.sea),
              ),
            ),
            const SizedBox(height: 5),
            Text('$daysLeft ${daysLeft == 1 ? "day" : "days"} out',
                style: const TextStyle(fontSize: 10, color: Palette.fog)),
          ],
        ),
      ),
    );
  }
}

class _CargoRow extends StatelessWidget {
  const _CargoRow({
    required this.resource,
    required this.held,
    required this.loaded,
    required this.pays,
    required this.bestPort,
    required this.onChanged,
  });

  final Resource resource;
  final double held;
  final double loaded;
  final double pays;

  /// Set when somewhere else pays better per day for this cargo.
  final String? bestPort;

  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final good = pays > 1.15;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(
          children: [
            Text(resource.icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(resource.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                      const SizedBox(width: 6),
                      Text('×${pays.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  good ? FontWeight.w700 : FontWeight.w400,
                              color: good ? Palette.moss : Palette.fog)),
                    ],
                  ),
                  Text(
                    bestPort == null
                        ? 'hold ${fmt(held)} · best here'
                        : 'hold ${fmt(held)} · ${bestPort!} pays better',
                    style: TextStyle(
                      fontSize: 10,
                      color: bestPort == null
                          ? Palette.moss
                          : Palette.fog.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: loaded > 0
                  ? () => onChanged((loaded - 25).clamp(0, held))
                  : null,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              color: Palette.fog,
            ),
            SizedBox(
              width: 40,
              child: Text(loaded.round().toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: loaded > 0 ? Palette.brass : Palette.fog)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: loaded < held
                  ? () => onChanged((loaded + 25).clamp(0, held))
                  : null,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              color: Palette.brass,
            ),
            GestureDetector(
              onTap: () => onChanged(held),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('all',
                    style: TextStyle(fontSize: 11, color: Palette.sea)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChandlerRow extends StatelessWidget {
  const _ChandlerRow({required this.controller, required this.resource});

  final GameController controller;
  final Resource resource;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final unit = s.chandlerPrice(resource);
    final most = s.chandlerMax(resource);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(
          children: [
            Text(resource.icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(resource.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                      const SizedBox(width: 6),
                      Text('${unit.toStringAsFixed(2)}c',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Palette.sea)),
                    ],
                  ),
                  Text('hold ${fmt(s.stock[resource])} · can take ${most.floor()}',
                      style: TextStyle(
                          fontSize: 10,
                          color: Palette.fog.withValues(alpha: 0.8))),
                ],
              ),
            ),
            for (final qty in [25.0, 100.0])
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: OutlinedButton(
                  onPressed: most >= qty
                      ? () =>
                          controller.act((g) => g.buyFromChandler(resource, qty))
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.brass,
                    side: const BorderSide(color: Palette.line),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 34),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: Text('+${qty.round()}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
