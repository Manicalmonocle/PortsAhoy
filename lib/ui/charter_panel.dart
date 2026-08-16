import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../sim/charters.dart';
import 'theme.dart';

/// Choose the standing conditions for the next voyage.
///
/// The budget line is the whole design in one number: advantages cost, and the
/// only way to afford more of them is to take a hardship that pays.
class CharterPanel extends StatelessWidget {
  const CharterPanel({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final p = controller.profile;
    final set = p.activeSet;
    final owned = kCharters.where((c) => p.owned.contains(c.id)).toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));

    if (owned.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Finish the Saltwind Light and the Admiralty will offer you a '
          'charter — a standing condition to carry into your next port.\n\n'
          'Hardships pay for advantages. You can only make something easier '
          'by first making something else harder.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.fog, height: 1.6),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _BudgetCard(set: set),
        const _Label('Hardships — these pay'),
        ...owned.where((c) => c.isHardship).map((c) =>
            _CharterTile(controller: controller, charter: c, set: set)),
        const _Label('Advantages — these cost'),
        ...owned.where((c) => !c.isHardship).map((c) =>
            _CharterTile(controller: controller, charter: c, set: set)),
        _RecordsCard(controller: controller),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: FilledButton(
            onPressed: () => _confirmNewRun(context),
            style: FilledButton.styleFrom(
              backgroundColor: Palette.brass,
              foregroundColor: Palette.deep,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(set.difficulty > 0
                ? 'Set sail — difficulty ${set.difficulty}'
                : 'Set sail'),
          ),
        ),
      ],
    );
  }

  void _confirmNewRun(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Palette.panel,
        title: const Text('Take a new post?'),
        content: const Text(
          'Your current port will be left behind for good. Charters and '
          'records are kept.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Stay here'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              controller.startNewRun();
            },
            child: const Text('Set sail',
                style: TextStyle(color: Palette.brass)),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.set});
  final CharterSet set;

  @override
  Widget build(BuildContext context) {
    final left = set.budgetLeft;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$left',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: left > 0 ? Palette.brass : Palette.fog)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('budget left to spend on advantages',
                      style: TextStyle(fontSize: 12, color: Palette.fog)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'You start with $kBaseBudget. Hardships pay you more. '
              'Earned ${set.budgetEarned + kBaseBudget}, spent ${set.budgetSpent}.',
              style: const TextStyle(
                  fontSize: 11, color: Palette.fog, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharterTile extends StatelessWidget {
  const _CharterTile({
    required this.controller,
    required this.charter,
    required this.set,
  });

  final GameController controller;
  final Charter charter;
  final CharterSet set;

  @override
  Widget build(BuildContext context) {
    final on = controller.profile.active.contains(charter.id);
    // Would turning this on break the budget?
    final affordable = on ||
        charter.isHardship ||
        set.budgetLeft >= -charter.weight;

    final accent = charter.isHardship ? Palette.rust : Palette.moss;

    return Card(
      color: on ? accent.withValues(alpha: 0.10) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: on ? accent : Palette.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: affordable
            ? () => controller.toggleCharter(charter.id)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 34,
                alignment: Alignment.center,
                child: Text(
                  charter.isHardship ? '+${charter.weight}' : '${charter.weight}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: affordable
                          ? accent
                          : Palette.fog.withValues(alpha: 0.4)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(charter.name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: affordable
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.45))),
                    const SizedBox(height: 2),
                    Text(charter.blurb,
                        style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: Palette.fog
                                .withValues(alpha: affordable ? 1 : 0.5))),
                    if (!affordable)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Take a hardship to afford this',
                            style: TextStyle(
                                fontSize: 10.5, color: Palette.lamp)),
                      ),
                  ],
                ),
              ),
              Icon(on ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: on ? accent : Palette.fog.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordsCard extends StatelessWidget {
  const _RecordsCard({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final best = controller.profile.bestByDifficulty;
    if (best.isEmpty) return const SizedBox.shrink();

    final keys = best.keys.toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Best runs',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 8),
            ...keys.map((d) {
              final r = best[d]!;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                          d == 0 ? 'No hardship' : 'Difficulty $d',
                          style: const TextStyle(
                              fontSize: 11, color: Palette.fog)),
                    ),
                    Text('${r.days} days',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Palette.brass)),
                    const Spacer(),
                    Text('${r.population} souls',
                        style: const TextStyle(
                            fontSize: 11, color: Palette.fog)),
                  ],
                ),
              );
            }),
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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
                color: Palette.fog)),
      );
}

/// Shown once, the moment the light is lit: pick one charter to keep.
class CharterOfferDialog extends StatelessWidget {
  const CharterOfferDialog({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final offered = controller.profile.pendingChoice
        .map(charterById)
        .whereType<Charter>()
        .toList();

    return AlertDialog(
      backgroundColor: Palette.panel,
      title: const Text('The light is lit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You finished on day ${controller.state.day} with a town of '
              '${controller.state.population}.\n\n'
              'The Admiralty offers you a charter to carry to your next port. '
              'Choose one — it is yours for good.',
              style: const TextStyle(height: 1.5, fontSize: 13),
            ),
            const SizedBox(height: 14),
            ...offered.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      controller.chooseCharter(c.id);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: c.isHardship ? Palette.rust : Palette.moss),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(c.name,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ),
                              Text(
                                  c.isHardship
                                      ? '+${c.weight} budget'
                                      : '${-c.weight} to use',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: c.isHardship
                                          ? Palette.rust
                                          : Palette.moss)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(c.blurb,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Palette.fog,
                                  height: 1.35)),
                        ],
                      ),
                    ),
                  ),
                )),
            if (offered.isEmpty)
              const Text('You hold every charter there is.',
                  style: TextStyle(color: Palette.fog)),
          ],
        ),
      ),
      actions: [
        if (offered.isEmpty)
          TextButton(
            onPressed: () {
              controller.chooseCharter('');
              Navigator.of(context).pop();
            },
            child: const Text('Back to the harbour'),
          ),
      ],
    );
  }
}
