/// The one animal a run gets to keep.
///
/// Pure data and a small lookup — no Flutter, like everything else under sim/.
///
/// A ship puts in around the midpoint with animals aboard and you buy one. It
/// is the only pet the run will ever offer: the moment a second is possible the
/// game stops being about which animal suits this run and starts being about
/// collecting the set, and a set to complete pulls the same way a rare drop to
/// chase does.
library;

import 'resources.dart';

enum PetKind { dog, cat, bird, monkey, turtle }

class Pet {
  const Pet({
    required this.kind,
    required this.name,
    required this.icon,
    required this.raises,
    required this.lowers,
    required this.why,
  });

  final PetKind kind;
  final String name;
  final String icon;

  /// The product it helps, and the one it costs you.
  final Resource raises;
  final Resource lowers;

  /// The reason, in the fiction. Shown on the card, because at this size the
  /// effect has to be legible or it may as well not exist — see [kPetBuff].
  final String why;

  String get id => kind.name;
}

/// What a pet is worth, and what it costs you elsewhere.
///
/// SMALL ON PURPOSE. A pet is a scheduled gift rather than something earned:
/// it arrives on a timer whatever you did, so a large number would let one
/// choice at the midpoint decide a run. The Grange — +20% to every shed, a
/// 24-day ramp, 400 coin and two hands — is what a real lever looks like here,
/// and a pet should read as an accent beside it.
///
/// The risk at this size is that nobody feels it, and there is precedent: five
/// separate "feels like nothing" reports in this project were every one a
/// visibility problem rather than a weak mechanic, and one of them was the
/// merchant at a 6% price edge. So the numbers below are only half the
/// feature; the other half is printing them where the player can see them, and
/// putting the animal somewhere they can watch it.
const double kPetBuff = 0.10;
const double kPetDrag = 0.07;

/// Meat eaten a day. An obligation, not a second herd.
///
/// 0.25, DOWN FROM 0.5, because at a half the feeding alone cost two days on
/// every pet — meat is scarce by design, being the thing that offsets what the
/// herds eat, and the town gets it first. Measured on the same 16 seeds, with
/// no pet at 81 days:
///
///     matched pick (turtle, bird)   81   <- free
///     mismatched   (monkey, dog)    84-85
///
/// A four-day swing between the best pick and the worst, which is what the
/// plan predicted and comfortably inside the ceiling it set. Note the shape:
/// a well-matched pet is FREE rather than fast, and a careless one costs. The
/// gift half of this is meant to be happiness, which does not exist yet — so
/// the probe can only see what a pet costs, and cannot yet see what it is for.
const double kPetAppetite = 0.25;

/// Coin asked for one, when the ship puts in.
///
/// Measured as costing nothing at all in days — a port at the midpoint can
/// find 400 — which is the right weight for something whose price is not
/// supposed to be the decision.
const int kPetPrice = 400;

/// Every product raised by exactly one pet and lowered by exactly one.
///
/// Dog, cat and bird close a ring — the dog's milk is undone by the cat, the
/// cat's grain by the bird, the bird's ore by the dog — and monkey and turtle
/// oppose straight across on timber and tools. Nothing here is strictly best,
/// because every pet's gift is another's cost, so the pick has to come from
/// which chains your run actually leans on.
///
/// NO PET TOUCHES MEAT. Meat is what pets eat, so one that raised it would be
/// partly feeding itself and its upkeep would stop being a cost — the one
/// thing every pet has in common. The dog is the obvious trap, since a herding
/// dog plausibly improves everything about a herd; it gets milk and nothing
/// else. `pets_test.dart` asserts both properties, because they are exactly
/// what a carelessly added sixth animal would break without anyone noticing.
const List<Pet> kPets = [
  Pet(
    kind: PetKind.dog,
    name: 'Dog',
    icon: '🐕',
    raises: Resource.milk,
    lowers: Resource.ore,
    why: 'Works the herd, and will not follow anyone down a shaft.',
  ),
  Pet(
    kind: PetKind.cat,
    name: 'Cat',
    icon: '🐈',
    raises: Resource.grain,
    lowers: Resource.milk,
    why: 'Keeps the rats out of the seed, and gets into the cream.',
  ),
  Pet(
    kind: PetKind.bird,
    name: 'Bird',
    icon: '🐦',
    raises: Resource.ore,
    lowers: Resource.grain,
    why: 'Reads the bad air below, and eats the seed above.',
  ),
  Pet(
    kind: PetKind.monkey,
    name: 'Monkey',
    icon: '🐒',
    raises: Resource.timber,
    lowers: Resource.tools,
    why: 'Goes up the stands like rigging, and loses every small iron thing '
        'it finds.',
  ),
  Pet(
    kind: PetKind.turtle,
    name: 'Turtle',
    icon: '🐢',
    raises: Resource.tools,
    lowers: Resource.timber,
    why: 'The smith works to its pace and spoils fewer pieces. Nothing about '
        'a turtle ever hurried a woodsman.',
  ),
];

Pet petByKind(PetKind k) => kPets.firstWhere((p) => p.kind == k);

Pet? petById(String id) {
  for (final p in kPets) {
    if (p.id == id) return p;
  }
  return null;
}
