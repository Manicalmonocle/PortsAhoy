# Livestock — design plan

**Status: planning only. Nothing here is built.** The point of writing it down
first is that this chain has one specific way of failing, and this project has
already failed that way twice.

---

## What the chain is for

**Livestock is not a food chain.** Its momentum comes from the goods — wool
into sailcloth, and cheese and bread onto the lighthouse bill. Those are what
the hands are spent on and what the run is won with.

The meat, milk and eggs exist for one purpose: **to cancel the grain the animals
eat.** The herds should not be a second town competing with the first for the
harvest. Feed them, get roughly the same food value back, and the grain question
stays a question about *timing* rather than a fight the player has to win.

That gives the chain a design target sharp enough to test:

> **Net food ≈ 0.** Whatever the animals eat, they return in food value.
> Everything the chain earns, it earns in wool, cheese and bread.

Read every number below against that. A livestock chain that *feeds* the port is
off-spec in one direction; one that starves it is off-spec in the other.

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

### Cheese and bread

One animal per product, which is how it was asked for and how it reads:

| Animal | Shed | Signature product | Also |
| --- | --- | --- | --- |
| **Cows** | Byre | Milk | Meat |
| **Chickens** | Hen House | Eggs | Meat |
| **Sheep** | Pasture | Wool | Meat |

Two of those reach the lighthouse by being made into something that keeps:

- **Cheese**, from milk.
- **Bread**, from eggs and grain, at the bakery.

Both land where the game is currently empty. The last timed unlock anywhere is
the distillery on day 25; from roughly day 30 to a finish near day 80-100,
nothing new is ever revealed. Bill items only reachable in the back half give
that stretch something to be *for*.

**There is no tallow.** An earlier draft of this document invented one — a
lighthouse needs something to burn, which made a lovely piece of fiction and
was never asked for. It had quietly become load-bearing across the whole plan.
If the bill ever wants a third new item, the lamp-fuel idea is a good one to
come back to; it should not be smuggled in as though it were part of the brief.

**The balance risk is unavoidable and must be paid for:** adding requirements
makes every run longer. The offset has to be explicit rather than hoped for, and
the survey says exactly where the slack is — planks and sailcloth both finish at
around a full bill over again in store, while rope comes in at 0.05x.

| | Now | Proposed |
| --- | --- | --- |
| Coin | 9,000 | 8,000 |
| Planks | 160 | **130** |
| Tools | 80 | 80 |
| Rope | 120 | 120 — *never cut this; it is what gates wins* |
| Sailcloth | 90 | 90 |
| **Cheese** | — | **40** |
| **Bread** | — | **50** |

### The fuller version: rewrite the bill around the animals

Rather than bolting one item on, the bill gets reworked so the new chain carries
real weight and the old chains give ground. Proposed:

| | Now | Proposed | Comes from |
| --- | --- | --- | --- |
| Coin | 9,000 | 8,000 | |
| Planks | 160 | **110** | sawmill |
| Tools | 80 | **55** | smithy |
| Rope | 120 | **120** | ropewalk, still flax — see below |
| Sailcloth | 90 | 90 | weaver, **now wool + rope** |
| **Cheese** | — | **40** | milk, from the byre |
| **Bread** | — | **50** | eggs and grain, at the bakery |

This is a bigger change than it looks, and it has two consequences worth
deciding deliberately rather than discovering.

#### Rope stays flax; sailcloth becomes wool **and** rope

The first draft of this section moved rope onto wool, and noted that doing so
would kill the flax decision. The better answer keeps rope on flax and makes
**sailcloth an assembly of wool and rope**:

```
flax → ropewalk → rope ─┬─→ the lighthouse bill
                        └─→ weaver ─→ sailcloth
wool (pasture) ─────────────→ weaver ─┘
```

**It preserves the decision instead of destroying it, by moving it downstream.**
What made flax interesting was one scarce thing feeding two things you both
need. That is now **rope**: every coil either goes on the bill or goes into a
sail, and you need both. The lighthouse comment's requirement — that the answer
has to be "both, eventually" — survives intact, and arguably sharpens, because
splitting a finished good is a more painful choice than splitting a raw.

Flax also stays essential rather than becoming single-purpose, since it is still
the only source of rope and rope now feeds two claims.

**And the fiction is better than either previous version.** Rope from wool was
never right — rope wants long bast fibre, which is the entire reason flax and
hemp were grown for it. But a **wool sail** is exactly right for this setting:
Norse and North Atlantic vessels carried them for centuries, and in a cold
archipelago it is the obvious cloth. Sails are also **bolt-roped** — rope sewn
along every edge to carry the load, without which the canvas tears itself apart.
So "sailcloth = wool cloth, roped at the edges" is not a concession to the
mechanic; it is how a sail is actually made.

##### What it costs, worked through

Present conversions: rope is 0.25 flax → 0.20 rope (**1.25 flax per rope**);
sailcloth is 0.45 flax → 0.18 sailcloth (**2.5 flax per sailcloth**). So today's
bill of 120 rope and 90 sailcloth consumes **375 flax**.

Proposed weaver recipe, as a starting point to measure:

```
inputs: {wool: 0.30, rope: 0.20} → outputs: {sailcloth: 0.18}
```

That is 1.67 wool and 1.11 rope per sailcloth, so 90 sailcloth wants
**150 wool and 100 rope**. Setting the bill's rope at **100** puts the split at
almost exactly half and half — 100 to the lighthouse, 100 into sails — which is
the shape that makes the choice bite hardest.

| | Now | Proposed |
| --- | --- | --- |
| Rope produced | 120 | **200** (100 bill + 100 weaver) |
| Flax consumed | 375 | **250** |
| Wool consumed | — | **150** |

Flax demand falls by a third and wool takes up the difference, which is the
correct direction: the new chain is carrying real weight rather than being
decoration.

**The load lands on the ropewalk, and that is the thing to watch.** It has to
produce 200 rope instead of 120 — a 65% increase. Fully crewed it makes
`0.20 × 3 × 24 = 14.4` a day, so that is about 14 days of uninterrupted full
production rather than 8, and a port may well need a second one. Its blurb
already warns that it "ties up hands"; under this bill it ties up considerably
more, and the labour warning at the top of this file applies directly. If the
median regresses, **the weaver's rope input is the first dial to turn**, before
touching the bill.

#### The town will eat your lighthouse bread

Cheese and bread are food, `_feedTown` draws food automatically, and the bill
wants them stockpiled. A port would watch its lighthouse provisions get eaten
by the people building it, with nothing on screen explaining why the pile keeps
shrinking.

**Fix — and it improves the fiction rather than compromising it.** Split each
into a perishable form and a keeping form:

| Perishable — the town eats these first | Keeps — and is what the bill wants |
| --- | --- |
| Fish, grain, meat, milk, eggs | **Cheese**, **Bread** |

Milk spoils and cheese keeps, which is the whole reason cheese exists; bread
keeps far better than the grain it was baked from. The eating order in
`_feedTown` puts them **last**, after fish, grain and meat — so the town only
reaches your lighthouse stores when it has genuinely run out of everything else.

**Yes, the town can eat the bill.** An earlier draft invented a separate
non-edible "biscuit" precisely so it could not. That was solving a problem the
game is content to have: a port that lets its larder empty deserves to watch the
cheese go, and it is avoidable by the ordinary means of keeping fish and grain
in store. It is the same call as leaving a consignment free to ship away the
food — *"if people trade too much that's on them."* One good, not two.

This also answers *why food belongs on a lighthouse bill at all*: **these are
the keeper's stores.** A lighthouse is manned and isolated, and you do not
finish one by building the tower — you finish it by victualling it so somebody
can live out there through a winter.

#### The real risk is the line-item count, not the quantities

The bill goes from four goods to seven. Every line item is a chain that must be
**built and staffed at the finish**, and workers are the binding constraint in
this game — that is the lesson at the top of this file. Smaller quantities do
not help with that: a shed has to be running at all to produce anything.

Under the proposed bill the endgame needs the sawmill, smithy, ropewalk, weaver,
pasture, byre, coop, bakery, dairy and farm all staffed at once. That is a
plausible way to make runs *longer* even though four of the five original
numbers went down.

One knock-on to remember: dropping tools from 80 to 55 softens the turtle and
monkey pets, which were both built around tools being the bottleneck.

**If the median regresses, cut in this order:** the weaver's rope input first
(it is a dial, not a feature), then bread, then cheese. Rope is last to be
touched and preferably never — it is what gates three wins in four.

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
| **Pasture** | Sheep | Wool, meat | 2 | ~30 days |
| **Byre** | Cows | Milk, meat | 2 | ~40 days |

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

**Milk → cheese → the lighthouse**, and **eggs + grain → bread → the
lighthouse**. These are the load-bearing ones: they are what makes the chain
part of the game rather than a side activity.

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

This is what makes the offset impossible to reach at believable quantities.
Animals do not convert feed to food one for one — really they convert it at a
heavy loss, which is why a herd is a store of value rather than a way to make
calories. If a pasture eats 3.5 grain a day and has to hand back 3.5 units to
break even, it is not a pasture, it is a very slow granary.

**Fix:** give `Resource` a `nutrition` field defaulting to 1.0, weight
`foodStock` by it, and have `_feedTown` draw weighted amounts. Meat around 3.0,
milk and eggs around 1.5. Then 3.5 grain a day comes back as roughly 1.2 meat,
which is a plausible yield *and* lands on the neutrality target. Contained — two
functions and one enum field — but it must land *before* livestock, not
alongside it.

**Tune feed and food output as one pair, never separately.** They are a single
number wearing two hats: the whole design intent is that they cancel.

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
2. **Median must not regress** against the honest baseline of **82 days**.
   Neutral is a pass; faster is a win. *(Was 96. The probe was leaving fourteen
   days on the floor through a housing bug — see below.)*
3. **Measure the bill rewrite separately from the chain.** They are two changes
   and they move the median in opposite directions — the animals add sheds and
   hands, while planks and tools coming down gives time back. Shipped together
   and measured together, a wash would look like success and neither half could
   be tuned. Three runs: chain only, bill only, both.
4. **At least one hard charter must improve.** A chain that only helps on easy
   runs is not pulling its weight — this is the shape spice was given, and it
   is the right one.
5. **Verify the sheds were staffed and ripened**, per above.
6. **The victory lap must not grow.** `tool/balance_probe.dart` reports the
   share of a run spent with nothing short of anything — currently a median of
   1%, and a played run described as "the perfect balance" was tense until day
   70 of 77, a lap of about 9%. **This is the measure livestock is most likely
   to ruin.** It adds production to a game whose interest comes from not having
   enough, and a median that improves while the lap grows to a third of the run
   is a worse game that measures better. If the lap passes ~15%, the chain is
   giving too much however fast it finishes.
7. **Run it with the chain disabled as a control.** The Grange's regression was
   only visible against a baseline measured the same week.

If 2 fails, cut in the order given under the bill rewrite: the weaver's rope
input, then bread, then cheese. Never rope.

---

## The bakery

Originally filed as a later follow-on. It has earned its way into the first
build instead — not as a food feature, but because it is the margin for error
on the neutrality target, and because it is what keeps grain from becoming a
fight between the town and the herds.

A bakery takes **grain and turns it into bread**, which feeds a person further
than the grain it came from. It unlocks late and it costs a shed, a worker and
a steady grain draw.

Three reasons it belongs with livestock rather than on its own:

**It shares the same prerequisite.** Bread is only meaningful once food is
weighted — with `foodStock` summing one unit per person-day, a loaf feeds
exactly as well as the grain it was baked from and the shed is pointless. The
`nutrition` field above unlocks both features; neither works without it, and it
is the same field that lets the herds hit their offset at believable yields.

**It is really a grain multiplier, and that is the whole job.** One loaf is
worth **2 to 3 grain** eaten raw, so the bakery does not make food — it makes
the grain the port already has go further. First pass:

```
1 grain → 1 bread,  bread nutrition 3.0      (a 3x multiplier on what passes through)
```

**The bar it has to clear is a farm worker, and that bar is higher than it
looks.** A farm hand produces `0.28 x 24 = 6.72` grain a day, which is 6.72
person-days of food. A baker only beats that if the extra food-days they unlock
exceed it. At `0.20` bread per tick with two workers the bakery turns 9.6 grain
into 9.6 bread a day — 28.8 person-days where the raw grain was 9.6, a **gain of
19.2 food-days across two hands, or 9.6 each.** That is about 1.4x a farm hand:
clearly worth building, without being so far ahead that a port would staff
bakeries and nothing else.

Worth noting how sensitive that is. At nutrition **2.5** the same shed gains 7.2
food-days per hand against the farm's 6.72 — a 7% edge, which is not worth a
building, a worker and a grain supply chain. **The difference between a good
feature and a pointless one here is half a point of nutrition**, so this is a
number to measure rather than to feel out.

**The throughput is the safety valve, not the ratio.** A 3x multiplier sounds
alarming — it is not, because the bakery can only ever multiply the grain it can
physically process. Capacity sets the ceiling on the whole effect, which makes
it the right dial to turn if food gets too easy.

**Bread is one good, and it is food.** It feeds the town at nutrition 3.0 and
it is what the lighthouse wants, which means the town *can* eat the bill if you
let the larder run dry — see the eating order above. An earlier draft split it
into an edible bread and an inedible biscuit to prevent that; one good is
simpler, and the failure is avoidable and the player's own.

### The bakery is the slack in the neutrality target

Livestock is meant to come out even on food, but "meant to" is doing real work
in that sentence. The herds eat through a thirty to forty day ramp before
returning much, the tuning will not be exact on the first pass, and the played
run showed a port with **no spare food at all** to absorb a miss.

The bakery is what makes a small miss survivable. It does not change the
neutrality target — that still has to hold on its own — but it means being
slightly wrong costs a slower month rather than a starved port. That is a better
reason for it to exist than "more food", and it argues for building it
**alongside** the first herd rather than after the chain is finished.

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

## What a played run changed about this plan

Build 1.6.1-29, no charters, difficulty 0, **won in 80 days** — a real player,
not the probe. Reference run
`human-2026-09-15-honest-80d.pa1`. Three things in it bear directly on
everything above.

### Food was at the growth gate for the last third of the run

`foodDays` over the closing stretch:

```
day 60  2.8      day 66  1.7      day 72  2.2      day 78  2.5
day 61  1.8      day 67  1.7      day 73  2.2      day 79  2.8
day 62  2.4      day 68  2.3      day 74  2.1      day 80  2.8
day 63  2.3      day 69  2.5      day 75  2.1
day 64  2.2      day 70  2.4      day 76  2.0
day 65  2.3      day 71  2.1      day 77  2.4
```

The gate is 2.0. This port sat on it for twenty days, dipping under on at least
three, and its population still climbed 29 to 37 — so growth was throttled
rather than stopped, which is exactly why it would never show up as a complaint.
**Food is not a solved problem in this game. It is the quiet ceiling on the back
half of a run.**

### The feed bill is smaller than it looks, because the food comes back

An earlier draft of this section read the 10 grain a day against the played
run's food economy — 37 people eating 37 a day with stores flat at two days'
worth — and concluded the herds would take 27% of the port's food from a port
with nothing spare, so the bakery had to come first or livestock would arrive as
a famine.

**That was reasoning about a food chain, and this is not one.** Under the
neutrality target at the top of this file, the grain goes in and comes back as
meat, milk and eggs of roughly the same food value. The port is not 27% poorer;
it is about level, having converted some grain into wool, cheese and bread
along the way. The bakery is a good idea on its own merits and stays in the plan, but it
is **not** a prerequisite, and livestock does not arrive as a famine.

What survives from that analysis is narrower and still true: the run had no
spare food, so **there is no slack to absorb a mistake here.** If the offset is
even slightly off — feed too high, nutrition too low, a ramp that eats for
thirty days before it returns anything — the shortfall lands on a port with
nothing in reserve. Which is the argument for tuning feed and output as one
pair, and for the chicken coop's short ramp leading the way in.

### What the probe can and cannot measure

Counting what was actually stopping the town from growing, over eight seeds:

```
                       roofs   payroll   food
before                    17         7      0
after the housing fix      6         8      0
```

The bot is never food-blocked, carrying twenty days in store where the played
run sat on the two-day gate for its final third.

An earlier draft called that a blocker for measuring livestock. **It is not** —
not for a chain that is food-neutral by design. There is no food benefit for the
bot to be too comfortable to notice. What the probe has to weigh is whether wool
cheese and bread pay for the sheds and hands they cost, and that lands on
days-to-lighthouse, which is the one thing the probe measures well.

Two real consequences remain:

- **Verify neutrality directly rather than inferring it.** Track the net food
  delta the chain causes and assert it is near zero. Do not expect a
  days-to-win number to reveal a food problem, because on this bot it cannot.
- **The bot's twenty-day surplus is its own inefficiency**, worth fixing
  eventually — hands on a fishing wharf that nobody needed are hands not making
  planks. That is a probe policy issue, not a livestock one.

The housing fix found along the way stands on its own: houses arrived only at
fixed slots in a thirty-item build order, so the port grew into its cap and
stopped — seventeen days a run with every roof taken. Reacting to the shortage
instead took the **median from 96 days to 82**, within two days of the human the
bot is calibrated against. It also settled the hiring question, parked on the
theory the bot was too poor for wages:

```
without --hire   median 82   roofs blocked  6
with    --hire   median 90   roofs blocked 18
```

Wages crowd out houses, and houses are worth more days than officers are —
worth remembering when the pets and the new sheds are priced, since they compete
for the same coin.

### The dark trade was available, and completely ignored

The reachability fix landed on 2026-08-16, well before this build, so the
distillery was available from day 25, the bonded cellar from day 22, and the
powder mill and privateer berth from day 49. The player built **none of the
four** and won comfortably.

That is the cleanest evidence yet for the rework: the dark trade was not merely
weak, it was not worth opening. It also means the changes since — spice, the
privateer captain, the prize bonuses — remain **unmeasured in a real run**, and
this report cannot speak to them, because it predates them.

Also worth noting: **no quartermaster was ever hired**, on a build where one
could be. The retinue went merchant, captain, captain, merchant. Retiring that
track in favour of automatic carting matched what a player was already doing.

---

## How close is this to shipping

**Nothing is built. This document is the whole of it so far.** The plan is
detailed, which makes it easy to mistake for progress; there is no code.

It is also, as written, **the largest change the game has had.** For scale: the
Grange was one building and two constants. This is up to eight new resources
(meat, milk, eggs, wool, cheese, bread), which would take the economy from 13
to 19 — every one of them needing a price, a category, market
behaviour, a storage row, a UI line and a run-code short code — across the
**13 files that touch `Resource.values`**. Plus four buildings, a rewrite of the
weaver's recipe, and a rewrite of the lighthouse bill.

### What has to land before any of it

1. **`Resource.nutrition`.** One enum field, plus `foodStock` and `_feedTown`.
   Both livestock and the bakery are meaningless without it.
2. **Probe crewing for maturity-ramped sheds.** `marginPerWorkerTick` scores
   them zero, so they go unstaffed and never ripen. Without this the
   measurement reports that livestock is worthless, exactly as it did for the
   grange and the privateer berth.

### One name is already taken

A building called **Coop** collides with **Cooperage** — the run code derives
three letters from the id, so both are `coo`, and `run_code_test.dart` asserts
against exactly that. It wants a different name: *Hen House* or *Poultry Yard*.
Cheap to fix now, confusing to hit later.

### Ship it in slices, not at once

Every large feature in this project so far has shipped whole, measured badly,
and been reworked: the grange made the bot slower, spice lost 8 of 8, the dark
trade was unreachable in a winnable run. A first slice small enough to measure
is the lesson those three keep teaching.

**Slice one — the loop, proved.** `nutrition`, one shed (sheep: wool and meat),
wool into the weaver, and the probe fix. Two new resources rather than eight,
one building rather than four, no bill rewrite. It answers the only question
that matters: *does a herd pay for the hands it costs?* If that fails, nothing
downstream was worth building.

**Slice two — the bill.** Cheese and the lighthouse rewrite, once slice one
holds. This is where the victory-lap measure earns its keep.

**Slice three — the rest.** Hen house, bakery and bread.

**Then pets**, which need the meat and the milk that slices one and three
supply.

### Still undecided

The open questions below are not filler — the wool-to-sailcloth ratio and
whether milk and eggs are one good or two both change what slice one even is.
They want answering before code, not during it.

---

## Open questions

- Wool-to-sailcloth ratio against the flax chain — needs both paths costed
  end to end before a number is picked.
- ~~Whether milk and eggs are one good or two.~~ **Settled: two.** Milk comes
  from cows, eggs from chickens, wool from sheep — one signature product each,
  with meat from all three.
- Whether the sheds unlock off the farm (like the Grange) or off the Grange
  itself. Off the Grange makes a clean two-stage route; off the farm makes
  livestock reachable without committing to the Grange first.
- Whether cheese needs a dairy of its own or comes off the byre directly. A
  separate shed is more faithful and costs another worker, which the labour
  budget above can probably not afford.
- What the bakery unlocks behind. A day gate fills the empty stretch most
  reliably; hanging it off the warehouse ties it to the chain it belongs to.
- Whether the bakery's worker is affordable at all, given the labour budget.
  It may only pay for itself once livestock is competing for the same grain,
  which is an argument for building it second rather than first.
