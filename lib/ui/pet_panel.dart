/// The ship with animals aboard, and the animal you keep.
///
/// Two halves of one job. The offer is the mid-game beat — the only new thing
/// the game reveals between day 25 and the light — and the card is what stops
/// the pet becoming another quiet feature.
///
/// THE NUMBERS ARE THE FEATURE. A pet moves one product by 10% and another by
/// 7%, which is small enough that nobody will ever feel it by playing; this
/// project has had five separate "feels like nothing" reports and every one was
/// a visibility problem rather than a weak mechanic. So both effects are
/// printed, in figures, wherever the pet appears — at the moment of choosing
/// and every time afterwards.
library;

import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../sim/pets.dart';
import 'theme.dart';

/// The one animal this port keeps, shown under the retinue where the rest of
/// "your people" live.
class PetCard extends StatelessWidget {
  const PetCard({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final pet = s.petDef;
    if (pet == null) return const SizedBox.shrink();

    final fed = s.petFed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(pet.icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(pet.name,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(width: 8),
              if (!fed)
                const Text('hungry',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Palette.rust)),
            ],
          ),
          const SizedBox(height: 3),
          // Struck through when hungry rather than hidden: a player who cannot
          // see what they are missing cannot tell a sleeping buff from one
          // that was never real.
          Text(
            '+${(kPetBuff * 100).round()}% ${pet.raises.label.toLowerCase()}'
            '   ·   −${(kPetDrag * 100).round()}% '
            '${pet.lowers.label.toLowerCase()}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fed ? Palette.moss : Palette.fog.withValues(alpha: 0.45),
              decoration: fed ? null : TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            fed
                ? '${pet.why}  Eats $kPetAppetite meat a day.'
                : 'No meat in the stores, so it is not working. Feed it and '
                    'it picks straight back up.',
            style: const TextStyle(
                fontSize: 11, color: Palette.fog, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// The ship still at the quay, for a player who kept her waiting.
///
/// The other half of the fix above: a deferred offer that left nothing on
/// screen would be a feature the player had dismissed into thin air, and this
/// project has had five "feels like nothing" reports that were every one of
/// them a visibility problem. She sits where the kept pet would sit, so the
/// slot means the same thing before and after.
class PetOfferCard extends StatelessWidget {
  const PetOfferCard({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    if (!s.petOfferOpen) return const SizedBox.shrink();
    final short = kPetPrice - s.coin;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: InkWell(
        onTap: () => showDialog<bool>(
          context: context,
          builder: (_) => PetOfferDialog(controller: controller),
        ),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Palette.deep,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Palette.line),
          ),
          child: Row(
            children: [
              const Text('🐾', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('A ship with animals aboard',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      short > 0
                          ? 'Waiting at the quay. $kPetPrice coin — '
                              '$short short.'
                          : 'Waiting at the quay. $kPetPrice coin, and you '
                              'have it.',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: short > 0 ? Palette.fog : Palette.moss),
                    ),
                  ],
                ),
              ),
              const Text('›',
                  style: TextStyle(fontSize: 18, color: Palette.fog)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown once, when the ship puts in. Pick one, wave them on, or keep her
/// waiting.
class PetOfferDialog extends StatelessWidget {
  const PetOfferDialog({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final canPay = s.coin >= kPetPrice;

    return AlertDialog(
      backgroundColor: Palette.panel,
      scrollable: true,
      title: const Text('A ship with animals aboard'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'She is selling, and she will not call again. One animal, '
            '$kPetPrice coin — and whichever you take, the port will find '
            'it is better at one thing and worse at another.',
            style: const TextStyle(
                fontSize: 12, color: Palette.fog, height: 1.4),
          ),
          const SizedBox(height: 12),
          ...kPets.map((p) => _PetChoice(
                pet: p,
                enabled: canPay,
                onTake: () {
                  controller.act((g) => g.takePet(p.kind));
                  Navigator.of(context).pop(true);
                },
              )),
          if (!canPay)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'You are ${kPetPrice - s.coin} coin short — so keep her '
                'waiting. She will not leave, and you will find her under '
                'Trade whenever the coin is there.',
                style: const TextStyle(fontSize: 11, color: Palette.rust),
              ),
            ),
        ],
      ),
      // THREE WAYS OUT, AND ONLY ONE OF THEM USED TO EXIST.
      //
      // This dialog is raised from inside build(), and the offer does not
      // expire — so dismissing it re-showed it on the very next rebuild, and
      // the port rebuilds every tick. A player caught 179 coin short had no
      // exit but to give up the run's only pet, and sat pinned while wages ate
      // the treasury: 221 coin on day 47, then 115, then 9, then nothing.
      // Reported as "can't minimize the popup to build the coin so I ran
      // completely out of coin", and it is exactly that.
      //
      // Waiting is free, and the fiction already said so: petOfferOpen has no
      // deadline, so "she is at the quay until you decide" was true. There was
      // simply no button for it. Popping false defers; popping true settles.
      actions: [
        TextButton(
          onPressed: () {
            controller.act((g) => g.declinePet());
            Navigator.of(context).pop(true);
          },
          child: const Text('Let them sail on'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep her waiting'),
        ),
      ],
    );
  }
}

class _PetChoice extends StatelessWidget {
  const _PetChoice(
      {required this.pet, required this.enabled, required this.onTake});

  final Pet pet;
  final bool enabled;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: enabled ? onTake : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Palette.deep,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: enabled ? Palette.line : Palette.line.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pet.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pet.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    // Both halves, in figures, before you pay. A cost you find
                    // out about afterwards is a trap, not a trade-off.
                    Text(
                      '+${(kPetBuff * 100).round()}% '
                      '${pet.raises.label.toLowerCase()}'
                      '   ·   −${(kPetDrag * 100).round()}% '
                      '${pet.lowers.label.toLowerCase()}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Palette.moss),
                    ),
                    const SizedBox(height: 2),
                    Text(pet.why,
                        style: const TextStyle(
                            fontSize: 11, color: Palette.fog, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
