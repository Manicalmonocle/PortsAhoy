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
| Buff | **+10%** | A nudge, not a lever — see below |
| Debuff | **−7%** | Enough that a careless pick costs something |
| Happiness | small, permanent | The constant sweetener, so any well-matched pet beats no pet |
| Meat eaten | **~0.5/day** | A nuisance, not a second herd |

**Buff slightly exceeding debuff is deliberate.** A well-matched pet should
clearly pay; the skill is in the matching, not in overcoming a tax. A mismatched
pet still hurts, because −7% of something you depend on outweighs +10% of
something you do not.

**Why small.** A pet is a scheduled gift rather than something earned through
play — it arrives on a timer whatever you did. Big numbers on a free arrival
mean a run's outcome is substantially set by one choice at day 45, which is not
what this feature is for. The Grange, at +35% to *every* shed and a 35-day ramp
you paid 400 coin and two workers for, is what a real lever looks like here. A
pet should read as an accent next to it.

### The risk at this size is that nobody feels it, and there is precedent

This project has had **five separate "feels like nothing" reports, and every one
was a visibility problem rather than a weak mechanic.** One of them was the
merchant — `sellBonus: 1.06`, `voyagePay: 1.08`
([retinue.dart:213](../lib/sim/retinue.dart#L213)). A player bought it, saw
nothing, and said so. The fix was surfacing the number, not raising it.

**+10% is that same territory.** So at this magnitude, visibility is not polish,
it is the feature working at all:

- The pet's two effects stated plainly wherever the pet is, in numbers, always —
  not only at the moment of choosing.
- The affected product showing its modified rate, so the player can see milk
  running faster and ore running slower rather than taking it on faith.

A pet is easier to surface than the merchant was, in fairness: its effect lands
on one named product rather than diffusely across every price, so there is
somewhere obvious to print it.

### What to expect from the measurement

Written down first, so the result can disagree with it.

A pet arrives around day 45 of an ~82-day run, so roughly **37 days of effect**.
If the affected product is what the finish is actually waiting on, +10% saves
about a tenth of the time that product still needs — on ~25 days of accumulation
that is **2 to 3 days**. A mismatched pick should cost **1 to 2**. So the swing
between best and worst pick is around **4 days on an 82-day baseline**, or 5%.

**That is the intended size, not a disappointing one.** Pets are charm with a
minor effect; the goal is to be *felt*, not to be *decisive*. Which inverts what
the measurement is for.

### The measurement is a ceiling, not a floor

The usual question — "is this big enough to matter?" — is the wrong one here.
A pet that shifts the median by ten days would be a lever bolted onto a scheduled
free gift, and a run would turn on one choice at day 45. So:

- **Failing high is the real risk.** If the sweep shows +10/−7 moving the median
  much past ~4 days, it is overtuned and comes down.
- **A result inside the noise is acceptable**, so long as the UI delivers the
  perception. It is not evidence the numbers should rise.
- **+25/−20 is run as the reference for "too much"**, to confirm the shipped
  value sits well below it — not as a candidate to be promoted to.

### Perception comes from the UI and the world, not from the number

This is the whole trick, and the merchant proves it: its +8% was made to feel
real by *showing* it, and the number never changed. A charm feature has a second
channel the merchant never had, and for pets it probably carries more weight
than the arithmetic does:

- **The animal is visibly in the port.** It wanders the quay with the hands, who
  already walk around. A dog you can watch is doing more for perceptibility than
  any percentage, and it costs the balance nothing.
- **Both effects printed in numbers**, wherever the pet is, always — not only at
  the moment of choosing.
- **The affected product shows its modified rate**, so milk running faster and
  ore running slower are things you can read rather than trust.

Get those right and +10% is plenty. Get them wrong and no percentage would have
saved it — which is what five separate "feels like nothing" reports have already
demonstrated in this codebase.

### Why this lands where it does in the run

Consider the dog: **+10% milk** feeds cheese, which is on the lighthouse bill;
**−7% ore** slows tools, which are also on the bill. So the dog trades
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

1. **Honest baseline, median days.** Current baseline **82**.
2. **Sixteen seeds, not eight.** The predicted effect is about 4 days between
   the best and worst pick, against a seed spread of 24 days. Eight seeds cannot
   see that.
3. **Measure best pick and worst pick on the same seeds**, not against the
   baseline — the difference between them is the trade-off, and it is the only
   number here not swamped by seed variance.
4. **Pass is a ceiling.** The swing between best and worst should land near 4
   days and **must not exceed about 8**. A pet that decides runs is overtuned,
   whatever it does for engagement. A pet inside the noise passes, provided the
   UI carries the perception.
5. **Run +25/−20 as the "too much" reference**, to confirm the shipped value
   sits well under it.
6. **The victory lap must not grow.** The probe reports the share of a run
   spent with nothing short of anything — a median of 1% now, against a played
   run called "the perfect balance" that stayed tense to day 70 of 77. A pet is
   a small permanent gift arriving at the midpoint, which is exactly the shape
   that quietly removes the back half's tension. Watch this more closely than
   the median.
7. **Check the invariant by test**, not by eye: every product raised exactly
   once and lowered exactly once, and no pet touching meat.
