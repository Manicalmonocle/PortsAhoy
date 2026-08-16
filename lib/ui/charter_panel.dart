import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../sim/charters.dart';
import 'theme.dart';

/// Choose the standing conditions for the next voyage.
///
/// The budget line is the whole design in one number: advantages cost, and the
/// only way to afford more of them is to take a hardship that pays.
///
/// WHICH RUN AM I LOOKING AT. This screen shows two different runs at once, and
/// used to admit to neither. The charters a run is *being played under* are
/// snapshotted into [GameState.charters] the moment it begins and are fixed for
/// its whole length — nothing here can reach them. The toggles below belong to
/// the *next* voyage, and take effect only when you set sail, which abandons
/// the port you are in.
///
/// A player reported the confusion exactly: they began a voyage under a
/// hardship, found they could still toggle it, and reasonably assumed they were
/// altering the run in progress. They were not — but a screen that silently
/// applies your choices to a different run than the one you are staring at is
/// worse than one that refuses the change outright. So the run in force is now
/// shown first, plainly marked as settled, and the selection below says which
/// voyage it is for.
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
      // A ListView rather than bare padding: at a large text scale on a short
      // handset this copy is taller than the panel, and unscrollable text is
      // clipped text.
      return ListView(
        padding: const EdgeInsets.all(28),
        children: const [
          Text(
            'Finish the Saltwind Light and the Admiralty will offer you a '
            'charter — a standing condition to carry into your next port.\n\n'
            'Hardships pay for advantages. You can only make something easier '
            'by first making something else harder.\n\n'
            'A charter is settled when a voyage begins and holds for the whole '
            'run. Changing one means starting a fresh port from nothing.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.fog, height: 1.6),
          ),
        ],
      );
    }

    // What the run in progress is actually being played under. Fixed at the
    // moment it began; nothing on this screen can reach it.
    final live = controller.state.charters;
    final pending = _idsOf(p.active) != _idsOf(live.ids);

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _CurrentVoyageCard(controller: controller),
        _Label(pending ? 'Your next voyage — changed' : 'Your next voyage'),
        if (pending)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'These differ from the voyage you are on. Charters are settled '
              'when a run begins, so the changes below take hold only when you '
              'set sail — and setting sail leaves your current port for good.',
              style: TextStyle(
                  fontSize: 11, color: Palette.lamp, height: 1.45),
            ),
          ),
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
                ? 'Set sail anew — difficulty ${set.difficulty}'
                : 'Set sail anew'),
          ),
        ),
      ],
    );
  }

  /// Order-independent identity for a charter selection.
  static String _idsOf(Iterable<String> ids) {
    final list = ids.toList()..sort();
    return list.join(',');
  }

  void _confirmNewRun(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Palette.panel,
        title: const Text('Take a new post?'),
        content: Text(
          'Your port of ${controller.state.population} on day '
          '${controller.state.day} will be left behind for good, and the new '
          'run starts from nothing.\n\n'
          'This is the only way to change the charters you sail under. '
          'Charters you have earned, and your records, are kept.',
          style: const TextStyle(height: 1.5),
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

/// What the run in progress is settled under, and cannot be talked out of.
class _CurrentVoyageCard extends StatelessWidget {
  const _CurrentVoyageCard({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final live = s.charters;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Palette.brass),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 15, color: Palette.brass),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text('This voyage',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
                Text('day ${s.day}',
                    style: const TextStyle(fontSize: 11, color: Palette.fog)),
              ],
            ),
            const SizedBox(height: 8),
            if (live.active.isEmpty)
              const Text(
                'Sailing under no charter — a plain run, recorded at no '
                'difficulty.',
                style: TextStyle(
                    fontSize: 11.5, color: Palette.fog, height: 1.4),
              )
            else ...[
              ...live.active.map((c) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 26,
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            c.isHardship ? '+${c.weight}' : '${c.weight}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color:
                                    c.isHardship ? Palette.rust : Palette.moss),
                          ),
                        ),
                        Expanded(
                          child: Text(c.name,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white)),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 6),
              Text(
                'Recorded at difficulty ${live.difficulty}.',
                style: const TextStyle(fontSize: 11, color: Palette.fog),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Settled when this run began. Nothing below can change it — see '
              'it through, or set sail anew and start from nothing.',
              style:
                  TextStyle(fontSize: 11, color: Palette.fog, height: 1.4),
            ),
          ],
        ),
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
