# Pets — design plan

**Status: planning only. Nothing here is built.** Depends on
[the livestock chain](livestock.md), which supplies the meat.

---

## The shape, in one paragraph

A ship puts in around **day 40-50** with animals aboard and you buy **one**.
That is the only pet the run will ever offer. Every pet lifts happiness, raises
one product's yield and lowers another, and **eats meat**. The timing is not
decorative: the last timed unlock anywhere is the distillery on day 25, so from
about day 30 to a finish near day 80-100 the game reveals nothing new. This is
the beat that fills it.

Three knobs, and **only the first is random**: *when* is jittered inside the
window so it still surprises, *whether* is guaranteed, *which* is your pick.
That is what keeps it clear of a rare drop to chase.

---

## The table

Buffs act on **one product, not one shed**. A dog improves the herd's *milk*,
not everything the byre produces — see the rule below about meat.

| | Raises | Lowers | Why |
| --- | --- | --- | --- |
| **Dog** | Milk | Ore | Works the herd; will not follow anyone down a shaft |
| **Cat** | Grain | Milk | Keeps the rats out of the seed, and gets into the cream |
| **Bird** | Ore | Grain | A caged bird reads the bad air; it also eats the seed |
| **Monkey** | Timber | Tools | Goes up the stands like rigging, and loses every small iron thing it finds |
| **Turtle** | Tools | Timber | The smith works to its pace and spoils fewer pieces; nothing about a turtle ever hurried a woodsman |

**The invariant holds: five products, each raised by exactly one pet and lowered
by exactly one.** Milk (dog up, cat down), grain (cat up, bird down), ore (bird
up, dog down), timber (monkey up, turtle down), tools (turtle up, monkey down).
Dog, cat and bird close a ring; monkey and turtle oppose straight across.

Nothing is strictly best, because every pet's gift is another's cost. That is
worth asserting in a test — it is the property a carelessly added sixth animal
would break without anyone noticing.

### No pet may touch meat

Meat is what pets eat. A pet that raised meat yield would be **partly feeding
itself**, and its upkeep would stop being a cost at all — the one thing every
pet is supposed to have in common. The dog is the obvious trap here, since a
herding dog plausibly improves everything about a herd; it gets milk and nothing
else.

This is also why the buffs are per-product rather than per-shed. "Dog improves
the byre" would silently include the meat the byre produces.

---

## Numbers to start from

All first-pass, all to be measured. The relevant yardstick is the Grange at
`grangeMaxYield = 0.35` — **+35% to every shed**, ramped over 35 days. That is
the largest yield lever in the game, so a pet touching a single product must sit
well under it.

| | Value | Reasoning |
| --- | --- | --- |
| Buff | **+25%** | Felt on its axis over the ~35 days of run remaining, without rivalling the Grange |
| Debuff | **−20%** | Enough that a careless pick genuinely costs something |
| Happiness | small, permanent | The constant sweetener, so any well-matched pet beats no pet |
| Meat eaten | **~0.5/day** | A nuisance, not a second herd — see below |

**Buff slightly exceeding debuff is deliberate.** A well-matched pet should
clearly pay; the skill is in the matching, not in overcoming a tax. A mismatched
pet still hurts, because −20% of something you depend on outweighs +25% of
something you do not.

### Why this lands where it does in the run

Consider the dog: **+25% milk** feeds cheese, which is on the lighthouse bill;
**−20% ore** slows tools, which are also on the bill. So the dog trades
tools-speed for cheese-speed.

That makes the pet choice **a read on which bill item you are behind on** — and
day 40-50 is precisely when that first becomes knowable. The mid-game timing
was chosen to fill an empty stretch; it turns out to be the moment the decision
is most legible too.

### Feeding

**~0.5 meat a day**, against a port of 35-odd people eating 35. Small enough to
be an obligation rather than a second herd, large enough to notice if the byre
stalls.

**An underfed pet must never die.** It should work poorly — buff suppressed,
happiness dampened — until it is fed again. Recoverable, legible, and not a
punishment loop. Losing a pet to a bad week is the wrong kind of pressure, and
the ramp on livestock means a shortage is rarely the player's fault alone.

---

## The gating problem, and the fix

Pets eating meat means **one optional system now gates another**: a port that
never builds a byre cannot keep a pet, and the promise above — *every run gets
the offer, exactly once* — would quietly become false.

**Fix: meat is purchasable at the import berth.** A port without livestock can
still feed a pet by buying meat, at a price. The offer stays universal, the
herd becomes the cheap path rather than the entry fee, and taking a pet before
you have a byre becomes a real decision rather than a locked door.

This also gives meat a job it was missing. In the livestock plan meat exists to
cancel the grain the herds eat, which is a passive role. Pets give it an active
sink and a reason to keep a surplus.

---

## What has to exist first

1. **`Resource.nutrition`**, from the livestock plan. Meat has to be worth more
   than a fish per unit or none of the food arithmetic works.
2. **Livestock**, for milk and meat. Two of the five pets point at products that
   do not exist yet.
3. **Per-product yield scaling.** `EventDef.yieldScale` is per-*building*, which
   is the wrong granularity — it cannot express "the byre's milk but not its
   meat". This is new machinery, not a reuse.
4. **A scheduled once-per-run event with a choice.** Also new: the event system
   draws one weighted event a day with a repeat guard, and every entry in the
   catalogue is something that happens *to* the player. A guaranteed beat that
   stops and asks a question is neither.

---

## The bar

1. **Eight seeds**, honest baseline, median days. Current baseline **82**.
2. **A well-matched pet should be worth something measurable** — if +25% on one
   product for the back half of a run does not move the median at all, the
   numbers are too small to bother with.
3. **A mismatched pet should cost.** Measure the worst pick as well as the best;
   if both are neutral, the trade-off is decorative.
4. **Check the invariant by test**, not by eye: every product raised exactly
   once and lowered exactly once, and no pet touching meat.
