import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../sim/buildings.dart';
import '../sim/game_state.dart';
import '../sim/progression.dart';
import '../sim/resources.dart';
import 'theme.dart';

class BuildTab extends StatelessWidget {
  const BuildTab({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _LighthouseCard(controller: controller),
        if (controller.state.darkTradeOpen)
          _LetterCard(controller: controller),
        // Unlocked first, then what is still to come — so the tree ahead is
        // visible and motivating rather than a wall of everything at once.
        ...kBuildingDefs
            .where((d) => d.buildable && controller.state.isUnlocked(d.id))
            .map((d) => _BuildOption(controller: controller, def: d)),
        ..._locked(controller),
      ],
    );
  }
}

/// Buildings you have not earned yet, shown greyed with the one thing that
/// would unlock them.
List<Widget> _locked(GameController controller) {
  final locked = kBuildingDefs
      .where((d) => d.buildable && !controller.state.isUnlocked(d.id))
      .toList();
  if (locked.isEmpty) return const [];

  return [
    const Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Text(
        'STILL TO COME',
        style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w700,
            color: Palette.fog),
      ),
    ),
    ...locked.map((d) => _LockedOption(def: d)),
  ];
}

class _LockedOption extends StatelessWidget {
  const _LockedOption({required this.def});
  final BuildingDef def;

  @override
  Widget build(BuildContext context) {
    final rule = unlockRuleFor(def.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: [
            Opacity(
              opacity: 0.45,
              child: Text(def.icon, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(def.name,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.55))),
                  const SizedBox(height: 2),
                  Text(rule?.text ?? 'Not yet available',
                      style: const TextStyle(
                          fontSize: 11, color: Palette.lamp, height: 1.3)),
                ],
              ),
            ),
            const Icon(Icons.lock_outline, size: 16, color: Palette.fog),
          ],
        ),
      ),
    );
  }
}

class _LighthouseCard extends StatelessWidget {
  const _LighthouseCard({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state.lighthouseBuilt) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('🗼', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'The Saltwind Light stands. Day ${state.day}.',
                  style: const TextStyle(
                      color: Palette.lamp, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final coinPct = (state.coin / Balance.lighthouseCoin).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🗼', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('The Saltwind Light',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
                FilledButton(
                  onPressed: state.canBuildLighthouse
                      ? () {
                          controller.act((s) => s.buildLighthouse());
                          _celebrate(context, state);
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.lamp,
                    foregroundColor: Palette.deep,
                  ),
                  child: const Text('Raise'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Finish the port. This is the whole game — there is nothing to '
              'buy that brings it closer.',
              style: TextStyle(fontSize: 11, color: Palette.fog, height: 1.4),
            ),
            const SizedBox(height: 10),
            _Requirement(
              label: 'Coin',
              have: state.coin.toDouble(),
              need: Balance.lighthouseCoin.toDouble(),
              progress: coinPct,
            ),
            ...Balance.lighthouseCost.entries.map((e) => _Requirement(
                  label: e.key.label,
                  have: state.stock[e.key],
                  need: e.value,
                  progress: (state.stock[e.key] / e.value).clamp(0.0, 1.0),
                )),
          ],
        ),
      ),
    );
  }

  void _celebrate(BuildContext context, GameState state) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Palette.panel,
        title: const Text('The light is lit'),
        content: Text(
          'You finished the Saltwind Light on day ${state.day} with a town of '
          '${state.population}.\n\nNo ads were shown. Nothing was sold to you. '
          'You just ran a port well.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to the harbour'),
          ),
        ],
      ),
    );
  }
}

/// Lawful cover for prize tonnage.
///
/// The Admiralty will not deal with a port it already mistrusts, so this is the
/// fork in the layer: the Crown's commission, or the deep dark discount, never
/// both at once.
class _LetterCard extends StatelessWidget {
  const _LetterCard({required this.controller});
  final GameController controller;

  static const List<int> tonOptions = [50, 100, 200];

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final refused = !state.canBuyLetter;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📜', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Letter of Marque',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
                Text(
                  '${state.marqueTons} tons held',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: state.letterActive ? Palette.moss : Palette.fog),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              refused
                  ? 'The Admiralty will not seal a Letter for a port this '
                      'closely watched. Trade honestly for a while and ask again.'
                  : 'Makes a prize lawful. Boarding without one still works — it '
                      'is simply piracy, and the Crown notices.',
              style: TextStyle(
                  fontSize: 11,
                  color: refused ? Palette.rust : Palette.fog,
                  height: 1.4),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tonOptions.map((tons) {
                final coinCost = state.letterCoinCost(tons);
                final goods = state.letterCost(tons);
                final affordable = !refused &&
                    state.coin >= coinCost &&
                    state.stock.canAfford(goods);
                return OutlinedButton(
                  onPressed: affordable
                      ? () => controller.act((s) => s.buyLetterOfMarque(tons))
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.brass,
                    side: BorderSide(
                        color: affordable ? Palette.brass : Palette.line),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$tons t',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      Text(
                        '${coinCost}c · ${goods[Resource.sailcloth]!.round()} cloth'
                        ' · ${goods[Resource.tools]!.round()} tools',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement({
    required this.label,
    required this.have,
    required this.need,
    required this.progress,
  });

  final String label;
  final double have;
  final double need;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final done = progress >= 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: Palette.fog)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: Palette.deep,
                valueColor:
                    AlwaysStoppedAnimation(done ? Palette.moss : Palette.sea),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: Text(
              '${fmt(have)} / ${fmt(need)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                color: done ? Palette.moss : Palette.fog,
                fontWeight: done ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildOption extends StatelessWidget {
  const _BuildOption({required this.controller, required this.def});

  final GameController controller;
  final BuildingDef def;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final affordable = state.canBuild(def);
    final owned = state.buildings.where((b) => b.defId == def.id).length;

    final costParts = <String>[
      if (def.coinCost > 0) '${def.coinCost}c',
      ...def.cost.entries.map((e) => '${e.value.round()} ${e.key.label.toLowerCase()}'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                      if (owned > 0) ...[
                        const SizedBox(width: 6),
                        Text('×$owned',
                            style: const TextStyle(
                                fontSize: 12, color: Palette.sea)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(def.blurb,
                      style: const TextStyle(
                          fontSize: 11, color: Palette.fog, height: 1.35)),
                  const SizedBox(height: 5),
                  Text(
                    costParts.join('  ·  '),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: affordable ? Palette.brass : Palette.rust,
                    ),
                  ),
                  if (def.isProducer)
                    Text(
                      '${def.marginPerWorkerTick.toStringAsFixed(2)}c per worker-hour',
                      style: TextStyle(
                          fontSize: 10,
                          color: Palette.fog.withValues(alpha: 0.65)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  affordable ? () => controller.act((s) => s.build(def)) : null,
              style: FilledButton.styleFrom(
                backgroundColor: Palette.brass,
                foregroundColor: Palette.deep,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Build'),
            ),
          ],
        ),
      ),
    );
  }
}
