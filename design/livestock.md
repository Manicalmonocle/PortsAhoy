# Livestock — design plan

**Status: planning only. Nothing here is built.** The point of writing it down
first is that this chain has one specific way of failing, and this project has
already failed that way twice.

---

## The lesson that governs this

The Grange shipped in a raws-only form and made the balance bot **slower** —
100 days to 112. The reason was not the size of the bonus. It was that
**workshops in this game are worker-limited, not input-starved.** Handing a port
more raw material does nothing when every shed that could refine it is already
short of hands. The fix was to make the Grange lift *every* shed's yield, and
the median went to 96.

That mistake had already been made once before, with spice, and the spice
comment in [resources.dart](../lib/sim/resources.dart) spells it out:

> A subsystem that produces surplus coin cannot be worth the hands it costs.

Livestock is the third chance to make the same error, and it is the most likely
to, because animals look like they obviously produce value. The test for every
number below is not "is this a good yield" but **"does this pay back more than
the hands it takes away from the lighthouse bill?"**

---

## Why the lighthouse bill is the load-bearing part

The single most important thing in this plan is the request for animals to
*"add some new things to finish the lighthouse."* That is not decoration — it is
the mechanism that makes the chain matter at all.

The bill is 9,000 coin plus 160 planks, 80 tools, 120 rope and 90 sailcloth, and
the comment above it says why:

> Deliberately demands one good from every chain rather than a big pile of coin.

A chain whose output is *not* on that bill is optional, and an optimiser will
skip it — which is exactly what happened to the dark trade, which ended runs
3.8× richer and still lost 8 of 8, because coin was never the constraint.

So: **if livestock produces nothing the lighthouse wants, it will be correct to
ignore it.** Putting one animal product on the bill is what converts the whole
chain from a side activity into part of the game.

### Tallow

The proposed addition is **tallow**, rendered from cattle and sheep, and the
fiction could not be better: a lighthouse needs something to *burn*. The last
ingredient of the win condition being the fuel for the lamp itself is the
ending this game should have.

It also lands where the game is currently empty. The last timed unlock anywhere
is the distillery on day 25; from roughly day 30 to a finish near day 93-100,
nothing new is ever revealed. A bill item that only becomes reachable in the
back half gives that stretch something to be *for*.

**The balance risk is unavoidable and must be paid for:** adding a fifth
requirement makes every run longer. The offset has to be explicit rather than
hoped for. First pass to measure:

| | Now | Proposed |
| --- | --- | --- |
| Coin | 9,000 | 8,000 |
| Planks | 160 | 130 |
| Tools | 80 | 80 |
| Rope | 120 | 120 |
| Sailcloth | 90 | 90 |
| **Tallow** | — | **60** |

Planks and coin are the two most abundant items late, so they are the right
places to take it from. If median days still regresses, the tallow requirement
is too big — cut it before cutting anything else.

---

## The animals

Three sheds, mirroring the three animals, each with a **maturity ramp** reusing
the Grange's proven shape (`grangeMaturity`, 35 days to full) rather than
simulating individual beasts. Tracking a herd head by head is a great deal of
machinery for an effect a single scalar already expresses: *worth nothing the
week you buy it, worth a great deal by harvest.*

| Shed | Animal | Produces | Workers | Ramp |
| --- | --- | --- | --- | --- |
| **Coop** | Chickens | Eggs, meat | 1 | ~15 days |
| **Pasture** | Sheep | Wool, meat, tallow | 2 | ~30 days |
| **Byre** | Cattle | Milk, tallow, meat | 2 | ~40 days |

Cheap and quick at the chicken end, slow and expensive at the cattle end, so
the choice of which to build is a read on how long the run has left to run.

### Grain is the input, and it has to bite

**All three eat grain, every day, whether or not you are getting anything out
of them yet.** This is the single mechanic that keeps the chain honest: the farm
stops being a straight line to food and becomes a decision about what the grain
is *for*.

The rate has to be large enough to be felt. A fully-crewed farm produces
`0.28 × 4 workers × 24 ticks ≈ 27 grain a day`, so a feed bill of two or three
grain would vanish into the noise and the herd would be free. First pass:

| Shed | Grain per day | Share of one farm |
| --- | --- | --- |
| **Coop** | 1.5 | ~6% |
| **Pasture** | 3.5 | ~13% |
| **Byre** | 5.0 | ~19% |
| **All three** | **10.0** | **~37%** |

A port running the full set gives up better than a third of a farm to do it,
which means a second farm, or a bakery, or less bread on the table. That is a
real decision rather than a rounding error.

**Feed should scale with maturity**, from roughly 40% at a freshly built shed
to full at a grown herd. The cost then ramps alongside the benefit instead of
landing hardest on the day you can least afford it — and it keeps faith with
the Grange's bargain, where a new shed is *worth* little rather than *costing*
much.

**When the grain runs out, nothing dies.** Maturity stalls first; only a
prolonged shortage should walk it back, and slowly. A herd that starves to death
while you were busy is the punishment loop this game keeps refusing, and it
would be worse here than most because the ramp means you would lose forty days
of investment to one bad week.

**The shortage must be visible, and named.** `_feedTown` draws grain
automatically for the town, so a growing population can quietly eat the herd's
feed out from under it. The port would stop maturing for a reason found nowhere
on screen. The codebase already has the principle to follow, in `growthBlocker`:

> If something is holding the town back, say which thing.

The herd needs exactly that — *"the byre is short of grain"* — for the same
reason. Note that this makes **three claims on every sack**: the town, the herd,
and the bakery below.

**People eat before animals.** That ordering is not really in question, but it
is what creates the failure above, so it should be a deliberate choice recorded
here rather than a side effect of whichever code runs first.

### The labour budget is the hard constraint

**Total new worker slots across all three sheds: 5, and preferably fewer.**

Every hand in a byre is a hand not in the smithy making the 80 tools. Grazing
should be near-zero labour by design — the animals convert grain and time into
product on their own, and the worker count reflects tending rather than
operating. If these sheds end up wanting 8-10 hands between them, the chain
will lengthen runs no matter how good the products are, and no amount of yield
tuning will rescue it.

---

## Where each product goes

**Tallow → the lighthouse.** Covered above. The load-bearing one.

**Wool → the weaver → sailcloth.** Sailcloth is already on the bill at 90 and
currently comes only from flax. Wool gives it a second source, which is a real
strategic branch rather than a new tax — and it speaks directly to the flax
decision the lighthouse comment says it wants answered "both, eventually".

*Balance watch:* a second path to sailcloth can trivialise the flax chain. Wool
should convert at a worse rate than flax, or produce a distinct woollens good
that only partly substitutes. Measure both chains' end-to-end cost before
picking a ratio.

**Meat, milk and eggs → food.** Requested, and the right call — fish and grain
are the only two foods in the game, and the town's diet has been static since
day one.

**Meat → the pets.** Requested. See the trap below.

**Not in the first version: hides and leather.** Every new resource costs market
UI, storage, a run-code slot and tests, and this plan already adds five. Hides
are a good idea for later; they are not worth doubling the surface area now.

---

## Two problems to solve before any of this is built

### 1. Food is counted 1:1, so meat would be worse than fish

`foodStock` sums every `isFood` resource at one unit per person-day:

```dart
double get foodStock => Resource.values
    .where((r) => r.isFood)
    .fold(0.0, (s, r) => s + stock[r]);
```

One meat would feed exactly as many people as one fish, while costing grain, a
shed, a worker and forty days of ramp. Meat would be **strictly worse food than
fish** — the chain would be dead on arrival.

**Fix:** give `Resource` a `nutrition` field defaulting to 1.0, weight
`foodStock` by it, and have `_feedTown` draw weighted amounts. Meat around 3.0,
milk and eggs around 1.5. Contained — two functions and one enum field — but it
must land *before* livestock, not alongside it.

**Also decide the eating order.** `_feedTown` currently eats fish first on a
stated rule — "fish spoils, grain keeps". Salt meat keeps best of all, so it
should be eaten **last**: `fish → grain → meat`. That also stops the town from
automatically devouring the good you were saving for the lighthouse chain or
the pet.

### 2. Feeding pets with meat gates one optional system behind another

If the pet requires meat, then a run that never builds a byre cannot keep a
pet — and the pets plan promises **every run gets the offer, exactly once**.
That promise would quietly become false for any port that skipped livestock.

**Fix:** pets eat *any* food, and meat is simply the best of it. A fed pet
works; a well-fed pet works better and lifts happiness more. Every port can
feed an animal from a fishing wharf on day one, and the byre becomes an
upgrade rather than an entry fee.

**And an underfed pet must never die.** It should work poorly and dampen
happiness until it is fed again — recoverable, legible, and not a punishment
loop. A pet dying of neglect is the wrong kind of pressure for this game.

---

## What has to be fixed in the probe first, or the measurement is worthless

`tool/balance_probe.dart` ranks sheds by `marginPerWorkerTick` and **scores a
shed with no immediate outputs at zero**, so it never staffs one. This has
already silently wrecked two measurements:

- The **Grange** was never crewed, so it never ripened — the port paid 400 coin
  for a shed that did nothing, and the measurement blamed the mechanic.
- The **privateer berth** was never crewed, so the port built the whole dark
  chain, made the powder, and had nobody to board anyone with.

All three livestock sheds are maturity-ramped and will score exactly zero.
**They will not be staffed, they will not ripen, and the run will report that
livestock is worthless.** Explicit crewing for the coop, pasture and byre —
the same special-case the grange and berth already have — is a prerequisite,
not a follow-up.

Then assert it actually happened: **check herd maturity is non-zero at the end
of a probe run** before believing a single number it prints.

---

## The bar, agreed before the numbers are tuned

Set now, so the result cannot be argued into looking good later.

1. **Eight seeds minimum**, honest baseline, median days reported.
2. **Median must not regress** against the current honest baseline of 96 days.
   Livestock adds a bill item, so neutral is a pass; faster is a win.
3. **At least one hard charter must improve.** A chain that only helps on easy
   runs is not pulling its weight — this is the shape spice was given, and it
   is the right one.
4. **Verify the sheds were staffed and ripened**, per above.
5. **Run it with the chain disabled as a control.** The Grange's regression was
   only visible against a baseline measured the same week.

If 2 fails, the tallow requirement comes down before anything else is touched.

---

## Later: a bakery

Proposed as a follow-on rather than part of the first build, and it fits this
plan closely enough to record here.

A bakery takes **grain and turns it into bread**, which feeds a person further
than the grain it came from. It unlocks late and it costs a shed, a worker and
a steady grain draw.

Three reasons it belongs with livestock rather than on its own:

**It shares the same prerequisite.** Bread is only meaningful once food is
weighted — with `foodStock` summing one unit per person-day, a loaf feeds
exactly as well as the grain it was baked from and the shed is pointless. The
`nutrition` field above unlocks both features; neither works without it.

**It is really a grain multiplier, and that is what makes it worth a worker.**
Note that the growth gate is only `growthFoodDays = 2.0` — two days of buffer —
so raw food abundance is rarely what is holding a port back, and "more food"
alone would not justify the hands. What a bakery actually does is let the town
be fed on *less grain*, and the grain it frees is exactly what the herds eat.
First pass: **2 grain → 1 bread at nutrition 3.0**, so a bakery turns two
person-days of grain into three. Enough to matter, not enough to break the
farm.

**It sharpens the grain decision instead of softening it.** Livestock already
makes grain contested — feed the town or feed the herd. The bakery does not
resolve that tension, it raises the stakes on it, because now there are three
claims on every sack. That is the most interesting version.

It also lands in the right place on the clock. With the last timed unlock
sitting at day 25 and nothing revealed after it, a bakery arriving around day
35 alongside the livestock sheds starts repopulating the stretch of the game
that currently has nothing in it.

And it gives the happiness system its clearest signal. That plan already turns
on whether the town is *"fed well or merely fed"* — bread is what the
distinction was waiting for.

---

## Open questions

- Wool-to-sailcloth ratio against the flax chain — needs both paths costed
  end to end before a number is picked.
- Whether milk and eggs are distinct resources or one dairy good. Distinct is
  what was asked for and reads better; one good is materially less surface area.
- Whether the sheds unlock off the farm (like the Grange) or off the Grange
  itself. Off the Grange makes a clean two-stage route; off the farm makes
  livestock reachable without committing to the Grange first.
- Whether tallow needs a rendering step (a chandlery) or comes straight off the
  animal. A rendering shed is more faithful and costs another worker, which the
  labour budget above can probably not afford.
- What the bakery unlocks behind. A day gate fills the empty stretch most
  reliably; hanging it off the warehouse ties it to the chain it belongs to.
- Whether the bakery's worker is affordable at all, given the labour budget.
  It may only pay for itself once livestock is competing for the same grain,
  which is an argument for building it second rather than first.
