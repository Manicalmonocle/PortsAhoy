import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../sim/resources.dart';
import 'build_tab.dart';
import 'charter_panel.dart';
import 'event_banner.dart';
import 'hints.dart';
import 'world_view.dart';
import 'log_tab.dart';
import 'market_tab.dart';
import 'shed_list.dart';
import 'theme.dart';
import 'trade_panel.dart';

/// The base is the screen.
///
/// No tabs: the harbour fills the window and everything else floats over it as
/// a HUD or a panel you pull up and dismiss. That is the whole difference
/// between a base-builder and a spreadsheet with a picture at the top.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _Panel { none, build, quay, trade, log, sheds, charters }

class _GameScreenState extends State<GameScreen> {
  _Panel _panel = _Panel.none;
  int? _selected;
  bool _offerShown = false;

  /// The moment the light is lit, record the run and offer a charter. Guarded
  /// so a rebuild cannot show it twice.
  void _maybeOfferCharter(BuildContext context) {
    final c = widget.controller;
    if (!c.state.lighthouseBuilt || _offerShown) return;
    if (c.profile.runs.length > c.profile.wins) return;

    final alreadyRecorded = c.profile.runs.any((r) =>
        r.days == c.state.day && r.population == c.state.population);
    if (!alreadyRecorded && !c.profile.hasChoicePending) {
      c.recordVictory();
    }
    if (!c.profile.hasChoicePending) return;

    _offerShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CharterOfferDialog(controller: c),
      ).then((_) {
        if (mounted) setState(() => _panel = _Panel.charters);
      });
    });
  }

  void _open(_Panel p) => setState(() {
        _panel = p;
        _selected = null;
      });

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        // Gesture bar or three-button nav: everything that floats above the
        // dock has to clear it, or the bottom of the game is unreachable.
        final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
        _maybeOfferCharter(context);
        final hint = nextHint(state, controller.dismissedHints);
        final omens = state.events.omens(state.tick).toList();
        final live = state.events.live(state.tick).toList();

        return Scaffold(
          backgroundColor: const Color(0xFF12303F),
          body: Stack(
            children: [
              // 1. The base, filling the screen.
              Positioned.fill(
                child: WorldView(
                  controller: controller,
                  fullBleed: true,
                  selected: _selected,
                  onInspect: (i) => setState(() {
                    _selected = i;
                    _panel = _Panel.none;
                  }),
                  onTapEmpty: () => setState(() => _selected = null),
                ),
              ),

              // 2. HUD, then weather and nudges beneath it.
              //
              // One column rather than two guessed offsets: the banner used to
              // be pinned at a fixed top and landed on top of the resource
              // chips on a device with a taller status bar.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TopHud(controller: controller),
                    if (state.payrollAtRisk)
                      _StalledBanner(
                        icon: Icons.savings_outlined,
                        text: state.coin <= 0
                            ? 'The purse is empty and wages are going unpaid. '
                                'Sell something at the Quay.'
                            : 'About ${state.wageRunwayDays.floor()} days of '
                                'wages left in the purse. Sell something.',
                      ),
                    if (state.growthIsStalled && !state.payrollAtRisk)
                      _StalledBanner(text: state.growthBlocker!),
                    if (live.isNotEmpty || omens.isNotEmpty)
                      EventBanner(state: state),
                    if (hint != null)
                      HintCard(controller: controller, hint: hint),
                  ],
                ),
              ),

              // 4. The selected building's controls, floating over the base.
              if (_selected != null &&
                  _selected! < state.buildings.length)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: kDockHeight + safeBottom + 10,
                  child: _BuildingBubble(
                    controller: controller,
                    index: _selected!,
                    onClose: () => setState(() => _selected = null),
                  ),
                ),

              // 5. Collect-all, the one button you press most.
              if (state.hasAnythingToCollect && _selected == null)
                Positioned(
                  right: 12,
                  bottom: kDockHeight + safeBottom + 16,
                  child: _CollectAllButton(controller: controller),
                ),

              // 6. The dock.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Dock(
                  controller: controller,
                  onOpen: _open,
                ),
              ),

              // 7. Panels, as sheets over the base.
              if (_panel != _Panel.none)
                _PanelSheet(
                  controller: controller,
                  panel: _panel,
                  onClose: () => _open(_Panel.none),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

class _TopHud extends StatelessWidget {
  const _TopHud({required this.controller});
  final GameController controller;

  /// The handful of things worth a permanent slot. Everything else lives in
  /// the stores panel.
  static const List<Resource> pinned = [
    Resource.timber,
    Resource.planks,
    Resource.grain,
    Resource.fish,
  ];

  @override
  Widget build(BuildContext context) {
    final state = controller.state;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: Column(
          children: [
            // Every group scales down rather than overflowing: coin, day and
            // headcount all grow digits over a long game, and this has to fit
            // a 360dp phone at a large text scale.
            Row(
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        _Pill(
                          icon: '🪙',
                          label: fmt(state.coin),
                          colour: Palette.brass,
                        ),
                        const SizedBox(width: 6),
                        _Pill(
                          icon: '👣',
                          label: state.arrivalsThisTick > 0
                              ? '+${state.arrivalsThisTick} · '
                                  '${state.idleWorkers}/${state.population}'
                              : '${state.idleWorkers}/${state.population}',
                          colour: state.arrivalsThisTick > 0
                              ? Palette.moss
                              : (state.idleWorkers > 0
                                  ? Palette.lamp
                                  : Palette.fog),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      children: [
                        _Pill(
                          icon: '📅',
                          label: 'Day ${state.day}',
                          colour: Palette.fog,
                        ),
                        const SizedBox(width: 6),
                        _SpeedPill(controller: controller),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final r in pinned) ...[
                  Expanded(
                    child: _ResourceChip(
                      resource: r,
                      amount: state.stock[r],
                      cap: state.storageCapacity,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                _MiniButton(
                  icon: Icons.inventory_2_outlined,
                  onTap: () => _showStores(context, controller),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showStores(BuildContext context, GameController controller) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.hull,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final s = controller.state;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stores  ·  cap ${fmt(s.storageCapacity)} each',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 12),
                  ...Resource.values
                      .where((r) => !r.isContraband || s.darkTradeOpen)
                      .map((r) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Text(r.icon,
                                    style: const TextStyle(fontSize: 15)),
                                const SizedBox(width: 8),
                                SizedBox(
                                    width: 78,
                                    child: Text(r.label,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Palette.fog))),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: (s.stock[r] / s.storageCapacity)
                                          .clamp(0.0, 1.0),
                                      minHeight: 5,
                                      backgroundColor: Palette.deep,
                                      valueColor: AlwaysStoppedAnimation(
                                          s.stock[r] >=
                                                  s.storageCapacity - 1
                                              ? Palette.rust
                                              : Palette.sea),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 58,
                                  child: Text(fmt(s.stock[r]),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                ),
                                SizedBox(
                                  width: 52,
                                  child: Text(
                                      '${s.market.priceOf(r).toStringAsFixed(1)}c',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Palette.brass)),
                                ),
                              ],
                            ),
                          )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A one-line reason the town has stopped growing, right under the HUD where
/// the population figure is.
class _StalledBanner extends StatelessWidget {
  const _StalledBanner({required this.text, this.icon = Icons.people_outline});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Palette.lamp.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Palette.lamp),
            const SizedBox(width: 7),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 11, color: Palette.lamp, height: 1.3)),
            ),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.colour});
  final String icon;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colour)),
          ],
        ),
      );
}

class _SpeedPill extends StatelessWidget {
  const _SpeedPill({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final speed = controller.speed;
    return GestureDetector(
      onTap: controller.cycleSpeed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: (speed == 0 ? Palette.rust : Palette.brass)
                  .withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(speed == 0 ? Icons.play_arrow : Icons.fast_forward,
                size: 13, color: speed == 0 ? Palette.rust : Palette.brass),
            const SizedBox(width: 4),
            Text(speed == 0 ? 'Paused' : '${fmtSpeed(speed)}x',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: speed == 0 ? Palette.rust : Palette.brass)),
          ],
        ),
      ),
    );
  }
}

class _ResourceChip extends StatelessWidget {
  const _ResourceChip(
      {required this.resource, required this.amount, required this.cap});
  final Resource resource;
  final double amount;
  final double cap;

  @override
  Widget build(BuildContext context) {
    final full = amount >= cap - 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: full ? Palette.rust : Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(resource.icon, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              fmt(amount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: full ? Palette.rust : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, size: 15, color: Colors.white),
        ),
      );
}

// ---------------------------------------------------------------------------

class _CollectAllButton extends StatelessWidget {
  const _CollectAllButton({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final pending = controller.state.pendingCollection;
    return GestureDetector(
      onTap: () => controller.act((s) => s.collectAll()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Palette.brass,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download_rounded, size: 17, color: Palette.deep),
            const SizedBox(width: 6),
            Text('Collect ${fmt(pending)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Palette.deep)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Dock extends StatelessWidget {
  const _Dock({required this.controller, required this.onOpen});

  final GameController controller;
  final void Function(_Panel) onOpen;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final ships = state.market.ships.length;

    return Container(
      decoration: BoxDecoration(
        color: Palette.hull.withValues(alpha: 0.96),
        border: const Border(top: BorderSide(color: Palette.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              _DockButton(
                icon: Icons.add_home_work_outlined,
                label: 'Build',
                onTap: () => onOpen(_Panel.build),
              ),
              _DockButton(
                icon: Icons.sailing_outlined,
                label: 'Quay',
                badge: ships > 0 ? '$ships' : null,
                alert: state.cutterOnStation,
                onTap: () => onOpen(_Panel.quay),
              ),
              _DockButton(
                icon: Icons.swap_horiz,
                label: 'Trade',
                badge: state.voyages.isNotEmpty
                    ? '${state.voyages.length}'
                    : null,
                onTap: () => onOpen(_Panel.trade),
              ),
              _DockButton(
                icon: Icons.groups_outlined,
                label: 'Sheds',
                badge: state.idleWorkers > 0 ? '${state.idleWorkers}' : null,
                onTap: () => onOpen(_Panel.sheds),
              ),
              _DockButton(
                icon: Icons.map_outlined,
                label: 'Voyage',
                badge: state.lighthouseBuilt ? '!' : null,
                onTap: () => onOpen(_Panel.charters),
              ),
              _DockButton(
                icon: Icons.article_outlined,
                label: 'Log',
                onTap: () => onOpen(_Panel.log),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.alert = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon,
                      size: 22,
                      color: alert ? Palette.rust : Palette.fog),
                  if (badge != null)
                    Positioned(
                      right: -8,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: alert ? Palette.rust : Palette.brass,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(badge!,
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Palette.deep)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: alert ? Palette.rust : Palette.fog)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// A panel over the base. Dismiss by tapping the scrim or the handle.
class _PanelSheet extends StatelessWidget {
  const _PanelSheet({
    required this.controller,
    required this.panel,
    required this.onClose,
  });

  final GameController controller;
  final _Panel panel;
  final VoidCallback onClose;

  String get _title => switch (panel) {
        _Panel.build => 'Build',
        _Panel.quay => 'The Quay',
        _Panel.trade => 'Trade',
        _Panel.log => 'Log',
        // The panel shows the run you are on as well as the one you are
        // planning, so it cannot be titled for the next voyage alone.
        _Panel.charters => 'Charters',
        _Panel.sheds => 'Every shed',
        _Panel.none => '',
      };

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return Positioned.fill(
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onClose,
              child: Container(color: Colors.black.withValues(alpha: 0.45)),
            ),
          ),
          Container(
            // Sized against the space actually available, then padded past the
            // system bar, so the last row of a panel is never swallowed by the
            // navigation buttons.
            height: MediaQuery.of(context).size.height * 0.62 + inset,
            decoration: const BoxDecoration(
              color: Palette.deep,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(top: BorderSide(color: Palette.line)),
            ),
            padding: EdgeInsets.only(bottom: inset),
            child: Column(
              children: [
                GestureDetector(
                  onTap: onClose,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Row(
                      children: [
                        Text(_title,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        const Spacer(),
                        const Icon(Icons.keyboard_arrow_down,
                            color: Palette.fog),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _body()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() => switch (panel) {
        _Panel.build => BuildTab(controller: controller),
        _Panel.quay => MarketTab(controller: controller),
        _Panel.trade => TradePanel(controller: controller),
        _Panel.log => LogTab(controller: controller),
        _Panel.charters => CharterPanel(controller: controller),
        _Panel.sheds => ShedList(controller: controller),
        _Panel.none => const SizedBox.shrink(),
      };
}

// ---------------------------------------------------------------------------

/// The controls for one building, floating over the base right where you
/// tapped it — not buried in a list somewhere else.
class _BuildingBubble extends StatelessWidget {
  const _BuildingBubble({
    required this.controller,
    required this.index,
    required this.onClose,
  });

  final GameController controller;
  final int index;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final b = state.buildings[index];
    final def = b.def;
    final ready = b.hasCollectableOutput;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Material(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(14),
        elevation: 8,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Palette.brass.withValues(alpha: 0.7)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(def.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(def.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 17),
                    color: Palette.fog,
                    onPressed: onClose,
                  ),
                ],
              ),

              // What is waiting in the yard.
              if (def.outputs.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: b.holdFullness,
                          minHeight: 6,
                          backgroundColor: Palette.deep,
                          valueColor: AlwaysStoppedAnimation(
                              b.holdFullness >= 0.999
                                  ? Palette.rust
                                  : Palette.moss),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed:
                          ready ? () => controller.act((s) => s.collect(b)) : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Palette.brass,
                        foregroundColor: Palette.deep,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text('Collect ${fmt(b.holdTotal)}'),
                    ),
                  ],
                ),
                if (b.holdFullness >= 0.999)
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Text(
                      'The yard is full — the shed has stopped. Nothing is '
                      'lost, but nothing more is being made.',
                      style: TextStyle(fontSize: 10.5, color: Palette.rust),
                    ),
                  ),
                const SizedBox(height: 8),
              ],

              // Staffing.
              if (def.isStaffable)
                Row(
                  children: [
                    const Text('Hands',
                        style: TextStyle(fontSize: 12, color: Palette.fog)),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: b.workers > 0
                          ? () => controller
                              .act((s) => s.setWorkers(index, b.workers - 1))
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                      color: Palette.fog,
                    ),
                    Text('${b.workers}/${def.maxWorkers}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: (b.workers < def.maxWorkers &&
                              state.idleWorkers > 0)
                          ? () => controller
                              .act((s) => s.setWorkers(index, b.workers + 1))
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                      color: Palette.brass,
                    ),
                  ],
                ),

              // What it is doing, in words.
              Text(
                shedFlowLabel(b),
                style: const TextStyle(
                    fontSize: 11, color: Palette.sea, height: 1.35),
              ),
              if (def.imports) ...[
                const SizedBox(height: 8),
                CargoSelector(controller: controller, index: index),
              ],
              if (b.workers > 0 && b.lastEfficiency < 0.95)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(shedStarvedLabel(b),
                      style:
                          const TextStyle(fontSize: 11, color: Palette.rust)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
