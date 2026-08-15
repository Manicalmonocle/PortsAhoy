import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../sim/buildings.dart';
import '../sim/game_state.dart';
import '../sim/resources.dart';
import 'hints.dart';
import 'theme.dart';

/// "0.90 timber/h → 0.75 planks/h" at the current staffing.
String shedFlowLabel(Building b) {
  final def = b.def;
  if (b.workers == 0) return 'Unstaffed — ${def.blurb}';

  if (def.imports) {
    final spend = Balance.importCoinPerWorkerTick * b.workers;
    return '${spend.round()}c/h → ${b.importResource.label.toLowerCase()}';
  }
  if (def.isCrewed) {
    final ups = def.upkeep.entries
        .map((e) =>
            '${(e.value * b.workers).toStringAsFixed(2)} ${e.key.label.toLowerCase()}')
        .join(' + ');
    return 'crew stores: $ups /h';
  }
  if (def.concealPerWorker > 0) {
    return 'hides ${(def.concealPerWorker * b.workers).round()} units of contraband';
  }
  if (def.housing > 0) return 'houses ${def.housing}';
  if (def.storage > 0) return '+${def.storage.round()} storage per good';

  final ins = def.inputs.entries
      .map((e) =>
          '${(e.value * b.workers).toStringAsFixed(2)} ${e.key.label.toLowerCase()}')
      .join(' + ');
  final outs = def.outputs.entries
      .map((e) =>
          '${(e.value * b.workers).toStringAsFixed(2)} ${e.key.label.toLowerCase()}')
      .join(' + ');
  if (outs.isEmpty) return def.blurb;
  return ins.isEmpty ? '$outs /h' : '$ins → $outs /h';
}

String shedStarvedLabel(Building b) {
  if (b.def.imports) {
    return b.lastEfficiency <= 0.01
        ? 'Idle — no coin to spend'
        : 'Landing ${(b.lastEfficiency * 100).round()}% of its orders — short on coin';
  }
  if (b.def.isCrewed) {
    return b.lastEfficiency <= 0.01
        ? 'Crew stood down — no stores'
        : 'Crew at ${(b.lastEfficiency * 100).round()}% — short on stores';
  }
  return b.lastEfficiency <= 0.01
      ? 'Idle — no input to work with'
      : 'Running at ${(b.lastEfficiency * 100).round()}% — short on input';
}

/// Every shed in one scroll, for when you would rather read than tap around
/// the base. Same actions, different shape.
class ShedList extends StatelessWidget {
  const ShedList({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state.buildings.isEmpty) {
      return const Center(
        child: Text('Nothing built yet.',
            style: TextStyle(color: Palette.fog)),
      );
    }

    // One card per trade, not per shed. Cottages and warehouses are absent
    // entirely: there is nothing to assign to them, so a card is just
    // something else to scroll past.
    final types = state.staffableTypes;

    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      children: [
        _TownCard(state: state),
        if (types.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No sheds to work yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.fog)),
          ),
        for (final t in types)
          ShedGroupCard(controller: controller, defId: t),
      ],
    );
  }
}

/// Every shed of one trade, worked as a unit.
class ShedGroupCard extends StatelessWidget {
  const ShedGroupCard({
    super.key,
    required this.controller,
    required this.defId,
  });

  final GameController controller;
  final String defId;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final sheds = state.shedsOfType(defId);
    if (sheds.isEmpty) return const SizedBox.shrink();

    final def = sheds.first.def;
    final workers = sheds.fold(0, (a, b) => a + b.workers);
    final maxWorkers = def.maxWorkers * sheds.length;
    final held = sheds.fold(0.0, (a, b) => a + b.holdTotal);
    final canAdd = workers < maxWorkers && state.idleWorkers > 0;

    // Worst case across the group is what you need to act on.
    final worked = sheds.where((b) => b.workers > 0);
    final starved =
        worked.isNotEmpty && worked.any((b) => b.lastEfficiency < 0.95);
    final throttle = worked.isEmpty
        ? 1.0
        : worked.map((b) => b.eventThrottle).reduce((a, b) => a < b ? a : b);

    // Combined hourly flow at the current staffing.
    String flow() {
      if (workers == 0) return 'Nobody working — ${def.blurb}';
      if (def.imports) {
        final spend = Balance.importCoinPerWorkerTick * workers;
        return '${spend.round()}c/h → raw cargo';
      }
      if (def.isCrewed) return 'crew on standby';
      if (def.concealPerWorker > 0) {
        return 'hides ${(def.concealPerWorker * workers).round()} units';
      }
      final ins = def.inputs.entries
          .map((e) =>
              '${(e.value * workers).toStringAsFixed(1)} ${e.key.label.toLowerCase()}')
          .join(' + ');
      final outs = def.outputs.entries
          .map((e) =>
              '${(e.value * workers).toStringAsFixed(1)} ${e.key.label.toLowerCase()}')
          .join(' + ');
      if (outs.isEmpty) return def.blurb;
      return ins.isEmpty ? '$outs /h' : '$ins → $outs /h';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(def.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(def.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                          if (sheds.length > 1) ...[
                            const SizedBox(width: 6),
                            Text('×${sheds.length}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Palette.sea)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(flow(),
                          style: TextStyle(
                            fontSize: 11,
                            color: workers == 0
                                ? Palette.fog.withValues(alpha: 0.5)
                                : Palette.sea,
                          )),
                    ],
                  ),
                ),
                // One stepper for the whole trade: hands spread themselves
                // across the emptiest sheds.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: workers > 0
                          ? () => controller.act((s) => s.removeWorkerFrom(defId))
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                      color: Palette.fog,
                    ),
                    SizedBox(
                      width: 42,
                      child: Text('$workers/$maxWorkers',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: canAdd
                          ? () => controller.act((s) => s.addWorkerTo(defId))
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                      color: Palette.brass,
                    ),
                  ],
                ),
              ],
            ),
            if (held > 0.5) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text('${fmt(held)} waiting in the yards',
                        style: const TextStyle(
                            fontSize: 11, color: Palette.fog)),
                  ),
                  OutlinedButton(
                    onPressed: () => controller.act((s) {
                      for (final b in s.shedsOfType(defId)) {
                        s.collect(b);
                      }
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Palette.brass,
                      side: const BorderSide(color: Palette.brass),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Collect'),
                  ),
                ],
              ),
            ],
            if (starved) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: Palette.rust),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(shedStarvedLabel(worked
                        .reduce((a, b) =>
                            a.lastEfficiency <= b.lastEfficiency ? a : b)),
                        style: const TextStyle(
                            fontSize: 11, color: Palette.rust)),
                  ),
                ],
              ),
            ],
            if (throttle != 1.0 && workers > 0) ...[
              const SizedBox(height: 6),
              Text(
                throttle > 1.0
                    ? 'Running at ${(throttle * 100).round()}% — the weather is with you'
                    : 'Running at ${(throttle * 100).round()}% — conditions',
                style: TextStyle(
                    fontSize: 11,
                    color: throttle > 1.0 ? Palette.moss : Palette.lamp),
              ),
            ],
            if (def.imports) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < state.buildings.length; i++)
                if (state.buildings[i].defId == defId)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: CargoSelector(controller: controller, index: i),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TownCard extends StatelessWidget {
  const _TownCard({required this.state});
  final GameState state;

  @override
  Widget build(BuildContext context) {
    final idle = state.idleWorkers;
    final foodDays = state.foodDays;
    final hungry = foodDays < 3;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Stat(
                    label: 'Idle hands',
                    value: '$idle',
                    accent: idle > 0 ? Palette.lamp : Palette.fog),
                _Stat(
                    label: 'Population',
                    value: '${state.population}/${state.housingCapacity}'),
                _Stat(
                  label: 'Food left',
                  value:
                      foodDays.isFinite ? '${foodDays.toStringAsFixed(1)}d' : '—',
                  accent: hungry ? Palette.rust : Palette.moss,
                ),
                _Stat(
                    label: 'Wages/day', value: fmtCoin(state.dailyWageBill)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Roofs: ${state.housingBreakdown}',
                style: TextStyle(
                    fontSize: 10.5,
                    color: Palette.fog.withValues(alpha: 0.85))),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  state.isGrowing
                      ? Icons.trending_up
                      : (state.population >= state.housingCapacity
                          ? Icons.home_outlined
                          : Icons.warning_amber_rounded),
                  size: 14,
                  color: state.isGrowing ? Palette.moss : Palette.lamp,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(state.growthStatus,
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              state.isGrowing ? Palette.moss : Palette.lamp,
                          height: 1.3)),
                ),
              ],
            ),
            if (state.darkTradeOpen) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Stat(
                    label: 'The Crown',
                    value: state.noticeBand,
                    accent: state.notoriety <= Balance.patrolFloor
                        ? Palette.moss
                        : (state.notoriety < 45 ? Palette.lamp : Palette.rust),
                  ),
                  _Stat(
                    label: 'Exposed',
                    value: fmt(state.exposedUnits),
                    accent:
                        state.exposedUnits > 0 ? Palette.rust : Palette.moss,
                  ),
                  _Stat(
                      label: 'Hidden', value: fmt(state.concealCapacity)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.accent});
  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: accent ?? Colors.white)),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: Palette.fog.withValues(alpha: 0.75))),
          ],
        ),
      );
}

class BuildingCard extends StatelessWidget {
  const BuildingCard({
    super.key,
    required this.controller,
    required this.index,
  });

  final GameController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final b = state.buildings[index];
    final def = b.def;
    final starved = b.workers > 0 && b.lastEfficiency < 0.95;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(def.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(def.name,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(
                        shedFlowLabel(b),
                        style: TextStyle(
                          fontSize: 11,
                          color: b.workers == 0
                              ? Palette.fog.withValues(alpha: 0.5)
                              : Palette.sea,
                        ),
                      ),
                    ],
                  ),
                ),
                if (def.isStaffable)
                  _WorkerStepper(controller: controller, index: index),
              ],
            ),
            if (b.hasCollectableOutput) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: b.holdFullness,
                        minHeight: 5,
                        backgroundColor: Palette.deep,
                        valueColor: AlwaysStoppedAnimation(
                            b.holdFullness >= 0.999
                                ? Palette.rust
                                : Palette.moss),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => controller.act((s) => s.collect(b)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Palette.brass,
                      side: const BorderSide(color: Palette.brass),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text('Collect ${fmt(b.holdTotal)}'),
                  ),
                ],
              ),
            ],
            if (def.imports) ...[
              const SizedBox(height: 8),
              CargoSelector(controller: controller, index: index),
            ],
            if (starved) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: Palette.rust),
                  const SizedBox(width: 6),
                  Text(shedStarvedLabel(b),
                      style:
                          const TextStyle(fontSize: 11, color: Palette.rust)),
                ],
              ),
            ],
            if (b.eventThrottle != 1.0 && b.workers > 0) ...[
              const SizedBox(height: 6),
              Text(
                b.eventThrottle > 1.0
                    ? 'Running at ${(b.eventThrottle * 100).round()}% — the weather is with you'
                    : 'Running at ${(b.eventThrottle * 100).round()}% — conditions',
                style: TextStyle(
                    fontSize: 11,
                    color:
                        b.eventThrottle > 1.0 ? Palette.moss : Palette.lamp),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkerStepper extends StatelessWidget {
  const _WorkerStepper({required this.controller, required this.index});

  final GameController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final b = state.buildings[index];
    final canAdd = b.workers < b.def.maxWorkers && state.idleWorkers > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: b.workers > 0
              ? () => controller.act((s) => s.setWorkers(index, b.workers - 1))
              : null,
          icon: const Icon(Icons.remove_circle_outline),
          color: Palette.fog,
        ),
        SizedBox(
          width: 34,
          child: Text('${b.workers}/${b.def.maxWorkers}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: canAdd
              ? () => controller.act((s) => s.setWorkers(index, b.workers + 1))
              : null,
          icon: const Icon(Icons.add_circle_outline),
          color: Palette.brass,
        ),
      ],
    );
  }
}

/// Which raw cargo an import berth has standing orders for.
///
/// Deliberately a rate you point somewhere, never a basket of quantities.
class CargoSelector extends StatelessWidget {
  const CargoSelector(
      {super.key, required this.controller, required this.index});

  final GameController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final b = controller.state.buildings[index];
    return Wrap(
      spacing: 6,
      children: kImportables.map((r) {
        final selected = b.importResource == r;
        return GestureDetector(
          onTap: () => controller.act((_) => b.importResource = r),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:
                  selected ? Palette.brass.withValues(alpha: 0.22) : Palette.deep,
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: selected ? Palette.brass : Palette.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.icon, style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 5),
                Text(r.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? Palette.brass : Palette.fog,
                    )),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// One nudge at a time, dismissible, never blocking.
class HintCard extends StatelessWidget {
  const HintCard({super.key, required this.controller, required this.hint});

  final GameController controller;
  final HintDef hint;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF14323E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Palette.sea.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hint.title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Palette.sea)),
                  const SizedBox(height: 3),
                  Text(hint.body,
                      style: const TextStyle(
                          fontSize: 11, color: Palette.fog, height: 1.4)),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              color: Palette.fog,
              onPressed: () => controller.dismissHint(hint.id),
            ),
          ],
        ),
      ),
    );
  }
}
