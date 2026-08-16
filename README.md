# Ports Ahoy!

A tick-based resource management game for phones. You run a small trading port
in a cold archipelago: extract raw goods, refine them through production chains,
weather what the sea throws at you, and decide how much of the dark trade you
want a part of.

**No ads. No in-app purchases. No energy meters. No paid speed-ups.**

That is a design constraint, not a marketing line, and it is enforced
mechanically and by test:

| Free-to-play pattern | What this game does instead |
| --- | --- |
| Sell time skips on build timers | Fast-forward up to 4× is a free button |
| Cap offline progress, sell a bigger cap | Offline progress is uncapped; **storage you built** is the only limiter |
| Punish you for closing the app | **Nothing is ever seized while the app is closed** |
| Sell relief from a pressure meter | Notoriety has **no coin path down** and no passive decay — nothing to wait out |
| Gate content behind currency | The goal is a project you manufacture yourself |
| Sell a skip on a voyage | Nothing shortens a crossing. A better captain speeds up **future** voyages, never one already at sea |

The governing rule, asserted by test: **nothing anywhere shortens a duration.**
Voyages are the only thing in the game that takes time, and no coin, item,
building or action touches one. A voyage is also never a gate — your own quay
stays open the entire time — so a wait is a choice you make for a better price.

## Running it

The Flutter SDK is installed at `~/flutter`.

```sh
export PATH=$HOME/flutter/bin:$PATH
cd ~/ports_ahoy

flutter run -d chrome        # fastest iteration loop
flutter run -d <device-id>   # a plugged-in Android phone (flutter devices)
flutter build web --release  # what is currently tested
```

### Testing on a phone, without an Android build

The quickest route is the web build over your own network:

```sh
flutter build web --release
python3 -m http.server 8823 --bind 0.0.0.0 -d build/web
# then open http://<your-lan-ip>:8823 on the handset
```

### Building an APK

A JDK and the Android SDK are installed under `~/android` (no root, no Android
Studio — just the command-line tools):

```sh
export JAVA_HOME=$HOME/android/jdk
export ANDROID_HOME=$HOME/android/sdk
export PATH=$JAVA_HOME/bin:$HOME/flutter/bin:$PATH

flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

Flutter is already configured to find both (`flutter config --android-sdk
--jdk-dir`), so on this machine `flutter build apk` works from a clean shell
once those variables are exported.

Verify a change:

```sh
flutter analyze                     # clean
flutter test                        # 319 tests
dart run tool/balance_probe.dart    # 8-seed headless pacing check
dart run tool/balance_probe.dart --dark              # ...playing the dark trade
dart run tool/balance_probe.dart --charters=poor_soil  # ...under a hardship
```

## How the game works

Time runs in **ticks**; one tick is one game-hour, 24 ticks to a day.
Production happens every tick. Food, wages and population settle at day end.

### Chains

Extractors need no input (Forest Camp, Farm, Fishing Wharf, Flax Field, Mine).
Workshops refine (Sawmill, Ropewalk, Cooperage, Weaver, Smithy). A building runs
at the rate of its scarcest constraint — starved of input or out of storage
space, it throttles rather than cheating.

**The core tension is flax.** The Ropewalk and the Weaver both eat it, and
neither dominates:

- **Weaver** pays more per *worker* (2.16c vs 1.40c per worker-hour)
- **Ropewalk** pays more per *unit of flax* (9.6c vs 8.8c)

So when hands are scarce you staff the Weaver, and when flax is scarce you staff
the Ropewalk. A test (`ropewalk and weaver genuinely contend for flax`) stops a
future balance pass collapsing it into a dominant choice.

### The market

Every resource has a price index that mean-reverts toward 1.0. Selling in bulk
drives a price down for days; buying pushes it up. Diversifying beats optimising
one chain. Events add **exogenous** shocks on top — a frozen sound bids planks
up, a glut craters one trade, privateers in the lanes make every import dear.
Shocks decay on their own once the event lifts.

### The coin sink

The **Import Berth** is a shed whose input is coin: staff it and it spends coin
per worker-hour to land raw cargo at market price plus a factor's cut.

Two rules are written into the source and must not be broken:

1. **Never present imports as purchasable quantities.** It is a rate you staff,
   not a basket you check out. A rate cannot be repriced as a package without
   rebuilding the feature — which is what makes the shop shape impossible to
   slide in later.
2. **Never add a delay between paying and receiving.** Coin becomes cargo in the
   same tick, so no duration exists that a speed-up could be sold against.

It only ever lands raws (timber, flax, ore) — never a finished good and never
food. Every plank, rope, sailcloth and tool in the win condition still passes
through a shed you built and staffed.

### Weather and the world

15 events across a 120-day, four-season year. Every event **forewarns** with an
omen that states truthfully what is coming and for how long: duration, magnitude
and target are all rolled once at draw time and stored, so a save reloaded
mid-omen cannot reroll the outcome. Forewarning that lies is worse than none.

Guardrails, all tested:

- **Grace period** — nothing fires before day 12
- **One hazard at a time** — rolls defer rather than stack into a siege
- **Mercy floors** — a port already starving, broke or tiny draws only boons
- **Gap scales with capacity, not calendar** — a careful slow player is never
  punished for taking their time
- **Seasons** — the sound only freezes in winter, and it is the heaviest card in
  the deck, so days 91–120 of every year are a stretch you can see coming thirty
  days out and stockpile against

### The dark trade

Entirely opt-in. Build any of the four dark sheds and free traders start
calling; build none and you will never see contraband, never be inspected, and
can still win.

- **Contraband** — Spirits (Distillery: grain + barrels) and Powder (Powder
  Mill: ore + timber). The distillery argues with the supper table every hour.
- **Notoriety** — rises only from explicit acts (selling contraband, bartering,
  holding it in plain sight, uncovered prize-taking, being caught). Falls only
  by honest commerce with Crown ships, and by a clean inspection. **There is no
  coin path down, and no passive decay.**
- **Concealment** — the Bonded Cellar hides 45 units per *hand posted to it*.
  Priced in workers, not coin, so it self-caps against housing and the surplus
  this layer exists to drain cannot switch enforcement off.
- **The Revenue** — above the patrol floor a cutter may put in, and boards 24
  hours later. **The inspection draws no randomness at all**: it seizes exactly
  what is exposed, which is arithmetic you could have done an hour earlier. No
  coin fine, and no legitimate good is ever taken — not a plank, not a tool, not
  a loaf, not a hand.
- **Two free actions** — scuttle (destroy it) or declare to customs (sell to the
  Crown at a poor price). Neither costs coin, neither needs a building, neither
  has a cooldown. Contraband is never a trap you cannot walk out of.
- **Rival raids** — keyed to the value of your hoard, not to a meter. Rivals
  ignore concealment, so the cellar protects you from the Crown and not at all
  from your own trade. That is what forces turnover instead of hoarding.
- **Prize-taking** — board a foreign hull *at your own quay*; it resolves in the
  same tick. Costs powder and a crewed Privateer Berth. A **Letter of Marque**
  makes it lawful; without one it is piracy and the Crown notices. The Admiralty
  refuses a port it already mistrusts, so the fork is real: the Crown's
  commission, or the deep dark discount, never both.

### Trade you start

The quay is reactive: ships arrive and you answer them. Two mechanics let you
take the initiative instead.

**The chandler** sells raw stock and food on demand at a 1.62× markup. A
shortage becomes something you fix now rather than something you wait out. It
is deliberately dearer than an Import Berth (1.45×, staffed, rate-limited) —
the berth is the efficient bulk pipe, the chandler is the premium for *now*.
It will not sell a finished good at any price; a test asserts every leg of the
win condition is absent from its stock list.

**Voyages** load your own cargo and send it to a port that actually wants it:

| | Days | Risk | Pays well for |
| --- | --- | --- | --- |
| Ostmark | 3 | 3% | rope, sailcloth, timber |
| Greyhaven | 5 | 7% | tools, barrels, powder |
| The Reaches | 9 | 14% | tools, sailcloth, spirits |

You get a quote up front, so the payoff is known before you commit. The point
is that a voyage **never touches your local price** — it is how you move volume
without collapsing your own market, paid for with cargo tied up and at risk.
Ten powder buys an escort and halves that risk; a privateer scare doubles it.

### The retinue

Three hiring tracks, three tiers each, hired in order. **Captains** cut crossing
time (−15/−28/−40%) and risk; **merchants** raise prices at home and abroad
(up to +20% at the quay, +26% on voyages); **quartermasters** cart your yards in
for you.

They cost coin to sign *and* a standing cost every day. That is the design: a
one-off purchase is a coin dump, a payroll is a decision you have to keep
affording. Pay someone off and it stops.

**Commission, and the bug that forced it.** The earners were once on a flat 5c a
day. Measured on a mid-game consignment, the first merchant returned +150c a
crossing against that 5c — a tenfold return that repaid its hire in four voyages
and printed money after. The fault was structural rather than numerical: *a flat
cost against a percentage benefit is always eventually free*, because the benefit
grows with your cargo all run while the cost does not. Tuning the 5c only moves
the day it stops mattering.

Captains and merchants are therefore paid the way factors and shipmasters
actually were — a small retainer plus a **commission** on what passes through
their hands (3–8% for a captain, 3.5–11% for a merchant). The cost now scales
with the benefit. A captain is the interesting case: commission is a *pure* cost
to them, so a retained captain makes every crossing quicker and safer and pays
*less* per voyage — the gain has to come from sailing more of them. The
quartermaster stays on a flat wage, since carting earns nothing to take a cut of.

**Officer berths.** A port supports one officer until 9 **staffed** sheds, two
until 16, three after. The first hire is a choice between price, speed and having
your yards carted — not the first item on a shopping list you will finish anyway.
Promoting someone you already retain never needs a new berth. In a probe run the
second berth opened on day 50 and the third on day 88, against a win around 116.

Staffed, not built, and the distinction is the whole gate: an empty shed costs
nothing to keep, so counting built ones let a player throw up cheap huts nobody
worked in and buy all three berths outright for a few hundred coin. A working
port supports officers; a field of empty huts does not.

"Working shed" means `BuildingDef.isProducer` — anything that draws hands and
does something with them, which includes the **Import Berth**. It has no
`outputs` map (it spends coin by the hour and lands raws by another path), so an
earlier check for outputs alone ignored a shed with three hands in it. It is
absent from the *quartermaster's* count on purpose, though: imports land in the
stores rather than a yard, so there is nothing there to cart.

**Seeing them work.** A consignment quote is itemised — cargo value, what the
factor added, what they took back, the harbour charter, and what actually
reaches you — and the crossing shows the lane's own length against the one your
captain will sail. The quay rows name the factor's net price per unit. All of it
is computed by the sim and handed to the panel rather than reassembled in the
UI, because a breakdown that does its own arithmetic will eventually disagree
with the figure beside it.

Showing the number is what caught the next bug: crossings were rounded to whole
days, so a first captain on the 3-day lane turned 2.55 into 3 and delivered
nothing while still charging commission — a trap on the shortest, most-used
route, bought by the first hire of a run. Crossings are measured in hours now,
and every captain tier saves real time on every lane, which a test asserts.

### Saving

The game autosaves every ten seconds while the clock runs, on every deliberate
action, and the moment the app is backgrounded or the tab hidden.

This is worth writing down because for most of the project's life it did none of
those things. `GameController.save()` existed, was correct, and **had no caller
anywhere in `lib/`** — no lifecycle observer, no timer, no button. Every run
lived in memory and died with the process, and the offline catch-up in `load()`
could never fire because nothing had ever written a timestamp for it to read.

The test suite did not catch it for a simple reason: the test called `save()`
itself, so it proved that saving *works* rather than that the game *does it*.
There is now a second test that refuses to call `save()` and asserts a played
run comes back anyway; it fails against the old code, which is the only reason
to trust it.

### Is the dark trade worth it?

A player's verdict, after several full runs: *"I skip it because it doesn't
feel worth the investment. It doesn't speed up progress or anything, just adds
another layer for no real payoff."*

Measured rather than argued. Per worker-hour at base prices the honest Smithy
pays 2.85 and the Distillery 1.50, so contraband **sold for coin is 0.53x the
best honest chain**. Counting the barter premium free traders pay for it
(parity 1.25-1.70 on bulk raws) it reaches 1.10x at typical parity and 1.36x at
best — and the layer still charges you hands in a cellar, permanent notoriety,
seizure of whatever is exposed, and raids keyed to the hoard.

Then the bot learned to play it (`--dark`), building the contraband chain in
place of the second smithy and weaver:

| | wins | win day (min / median / max) |
| --- | --- | --- |
| honest | 8/8 | 89 / 120 / 143 |
| dark | 8/8 | 82 / **108** / 120 |

So it is worth about **twelve days of a hundred and twenty** — real, and
completely invisible while every number on screen was one it *cost* you. The
port now keeps the other half of the account: what the dark trade has earned in
sales and barter margin, against what the Revenue and the rivals have taken.

This is the same shape as the merchant, and the third time a thing that "felt
like nothing" turned out to be a thing nobody was shown.

### Learning it

The port opens deliberately small: **two sheds and five hands**, which is one
idea — post people to work, cart in what they make. Everything else arrives
through an unlock tree, one building at a time, each earned by something you
did (`lib/sim/progression.dart`).

Locked buildings are still listed under **Still to come**, greyed, with the one
condition that opens them — so the shape of the game ahead is visible without
being dumped on you at once. Unlocks are checked the moment you collect, build
or turn a day, so the announcement lands next to the action that earned it, and
they are sticky: selling the timber that unlocked the sawmill does not take the
sawmill away.

Sheds hold a **week** of output in their yards, and every warehouse makes each
yard half again as big — so "my sheds keep filling up" has an answer you can go
and build rather than a stopwatch to obey.

### Goal

Raise the Saltwind Light: 9,000 coin + 160 planks + 80 tools + 120 rope +
90 sailcloth. It deliberately demands one good from every chain rather than a
pile of coin.

## Layout

```
lib/
  sim/            pure Dart, zero Flutter imports — the whole simulation
    resources.dart    resource table, prices, heat weights, ResourceBag
    buildings.dart    building catalogue + recipes (data-driven)
    market.dart       price indices, ships, free traders, barter, seeded PRNG
    terrain.dart      the island, generated from tile coordinates
    trade.dart        destinations and voyages
    retinue.dart      captains and merchants
    progression.dart  the unlock tree
    events.dart       event catalogue + scheduler (seasons, omens, mercy floors)
    game_state.dart   tick loop, population, imports, notoriety, the Revenue
  game_controller.dart  clock, speed, persistence, offline catch-up, hints
  ui/
    world_view.dart     the port as a real 3D scene — see below
    game_screen.dart    the HUD, the dock, and the panels over the base
    shed_list.dart      every shed in one scroll, and the shed controls
    market_tab.dart     the quay: cutter, crown ships, free traders, prizes
    trade_panel.dart    retinue, voyages, the chandler
    build_tab.dart      lighthouse, Letters of Marque, the catalogue
    hints.dart          contextual onboarding nudges
test/
  sim_test.dart          economy, imports, persistence, balance invariants
  events_test.dart       scheduling, eligibility, effects, determinism
  privateer_test.dart    notoriety, the Revenue, prizes, the honest path
  harbour_map_test.dart  plot layout + golden renders of the map
  app_test.dart          widget tests incl. four phone viewports
tool/
  balance_probe.dart   8-seed headless bot that plays full games
```

`lib/sim/` importing no Flutter is deliberate: the simulation is testable
without a widget tree, and the probe runs it headless at thousands of ticks per
second.

### The base is the screen

There are no tabs. The harbour fills the window and everything else floats over
it: a HUD along the top (coin, hands, day, speed, pinned resources), a dock
along the bottom (Build / Quay / Trade / Sheds / Log) with live badges, and
panels that slide up and dismiss. Tapping a building brings its controls up in a
bubble over the base rather than sending you to another screen. A test asserts
`find.byType(TabBar)` finds nothing, so the spreadsheet cannot creep back.

**Sheds fill their own yards.** Production accumulates in the building until you
collect it — a brass bubble bobs over anything ready, and *Collect all* empties
the port in one press. A full yard stalls the shed, visible as the bubble
turning amber. Nothing is ever lost, so putting the phone down slows you but
never punishes you, and there is nothing to sell you to make it go away. Yards
hold four game-days, so offline progress is unaffected.

### The 3D view

`world_view.dart` is a real 3D scene, not an isometric one: a camera with a
position, a look-at target and a perspective frustum, with every polygon
projected through it. That buys three things a 2:1 diamond grid cannot have —
true perspective (near things are bigger, the ground converges), a camera you
can **orbit and tilt**, and per-face lighting from a fixed sun.

The island is geometry: water sits below sand, sand below grass, rock above
that, and every height change draws a cliff skirt down to its neighbour.
Buildings are boxes with pitched pyramid roofs. Picking is done by ray-casting —
your tap is unprojected and intersected with the ground plane — so tapping and
dragging stay accurate at any camera angle. Hold a building to pick it up and
drag it; target tiles light green if it fits and red if it does not.

It is one `CustomPainter`. The geometry is small enough that projecting and
depth-sorting it by hand each frame is cheaper than pulling in a 3D engine, and
it runs identically on web and mobile.

The scene is covered by a golden test. `flutter test --update-goldens` rewrites
`test/goldens/*.png`, which is the fastest way to actually *look* at a change —
it caught the camera framing empty water instead of the island, and back-face
culling that was dropping every roof.

## Balance notes

`tool/balance_probe.dart` plays eight fixed seeds with a competent-but-not-
optimal policy. It is a tuning instrument, not a test.

Current: **8/8 seeds win, median day 135, spread 53 days, peak coin 1.1× the
requirement.**

### Measured against a human

The clock has been set by playing, twice:

| base rate | one day at 1× | full run at 1× | verdict |
| --- | --- | --- | --- |
| 1.0 | 24s | ~55 min | "too quick to get a feel for what's going on" |
| 0.35 | 69s | ~2.6 h | "just a bit slow" |
| **0.70** | **34s** | **~1.3 h** | current — the pace that actually felt right |

The last row was not a guess. Playing at 0.35 felt sluggish at 1× but right at
2×, so 2× of 0.35 — 0.70 — became what 1× gives you. A comfortable default
should not be something the player has to reach for.

Speeds are `0, 0.5, 1, 2, 4`. The half step exists because 1× is now tuned to a
comfortable pace rather than a slow one, so watching the port closely needs
somewhere to go downward. 4× is a deliberate speedrun: one full playthrough
hunting bugs took 45 minutes at the old 4×.

That is the third of three readings, and the history is the point:

| | wins | median | spread | peak coin |
| --- | --- | --- | --- | --- |
| Before the coin sink | 6/8 | 200 | **296 days** | **10.6×** |
| After the Import Berth | 8/8 | 111 | 42 days | 1.0× |
| With events and the dark trade | 8/8 | 104 | **14 days** | 1.1× |

Four findings from the probe, each of which changed the design:

1. **A single seed lies.** One seed reported "day 200, peak coin 50k". Across
   eight seeds the real median peak was 95k and two seeds were *unwinnable*.
2. **The port could deadlock.** Ships originally only bought from you, so a
   player who sold their plank stock down could not build their way out —
   75,000 coin and permanently stuck at 13 buildings. Fixed by making trade
   bidirectional, then properly by the Import Berth.
3. **A pure coin goal collapses late.** Income compounds until the number is
   trivial. Fixed by requiring one good from every chain.
4. **Refining could destroy value.** The sawmill originally paid 0.5c per
   worker-hour against 0.6c for just selling the timber, and the weaver strictly
   dominated the ropewalk — so the flax tension the game is built around was not
   a real choice. Both are now locked by tests.

**The probe underestimates a real player's income by roughly 40% in the early
game.** Its selling heuristic holds a fixed reserve and only trades with
whoever happens to be at the quay. Measured: the cheapest retinue hire looked
affordable on day 23 by the model, and was bought on day 13 in play. Assume
anything priced against the probe will be reachable sooner than it says.

It has closed some of that gap. The bot now sends consignments, which it did not
do for most of the project — an omission that made the first merchant A/B as
worthless and measured a charter that does nothing but lengthen crossings at
exactly zero difficulty. With sailing added its range is 89-143 days against a
player's reported 94, where before its *best* seed was 105 and real play beat it
by eleven days.

**Known caveat:** the probe fully reallocates its labour every single day, so it
absorbs disruption a human never would. Events moved its median by only ~7 days;
expect them to bite considerably harder in real play. Do not tune event severity
against the bot.

All tuning lives in `Balance` in `lib/sim/game_state.dart` and `EventTuning` in
`lib/sim/events.dart`. The building and event catalogues are plain `const`
lists — adding a chain or an event is one entry.

## What is not built yet

- No sound, no animation beyond the harbour swell, emoji placeholder art
- No tech or upgrade progression beyond building more sheds
- The archipelago/trade-route map (ships' origins, lanes, blockades) — only the
  harbour scene exists
- **The bot still does not hire a retinue or use the chandler**, so pacing
  measured against it ignores two systems a real player leans on. It does send
  consignments and can work the dark trade (`--dark`) — both were added after
  their absence produced two wrong readings.
- Not on the Play Store. That needs twelve testers running a closed track for
  fourteen unbroken days; internal testing does not count toward it.

### What used to be here, and is no longer true

This section claimed for a long while that the game had **never been played by a
human**, had **never run on a physical device**, and that **no Android build had
ever been produced**. All three are now wrong and were left stale far too long —
a README that overstates what is untested is as misleading as one that
overstates what works.

The game has been played through to the lighthouse repeatedly on a **Pixel 9 Pro
XL**, both as the installed APK and as the web build, in sessions of 45 to 55
minutes. Signed release APKs are produced routinely from this repo. And there is
now content past the lighthouse — a finished run earns a charter to carry into
the next one.

Nearly every bug of consequence in the last stretch came out of those sessions
rather than out of the test suite: population stalling for eleven days, the
merchant being a formality, consignments not leaving the stores, the charter
screen describing the wrong run, an event whose description said nothing, the
import berth not counting as a working shed. The suite is 300-odd tests and
green throughout; play found what it could not.
