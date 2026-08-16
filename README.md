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
flutter test                        # 210 tests
dart run tool/balance_probe.dart    # 8-seed headless pacing check
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

Two hiring tracks, three tiers each, hired in order. **Captains** cut crossing
time (−15/−28/−40%) and risk; **merchants** raise prices at home and abroad
(up to +20% at the quay, +26% on voyages).

They cost coin to sign *and a wage every day*. That is the design: a one-off
purchase is a coin dump, a payroll is a standing decision you have to keep
affording. Pay someone off and the wage stops.

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

**Known caveat:** the probe fully reallocates its labour every single day, so it
absorbs disruption a human never would. Events moved its median by only ~7 days;
expect them to bite considerably harder in real play. Do not tune event severity
against the bot.

All tuning lives in `Balance` in `lib/sim/game_state.dart` and `EventTuning` in
`lib/sim/events.dart`. The building and event catalogues are plain `const`
lists — adding a chain or an event is one entry.

## What is not built yet

- **Never played by a human.** All balance evidence comes from a bot, and the
  bot does not hire a retinue, send voyages or use the chandler — so the
  reported pacing ignores three of the systems a real player will lean on.
- **Never run on a physical device** — only web plus widget tests at four phone
  viewports.
- **No Android build has ever been produced.** The dev sandbox has no Android
  SDK; see below.
- No sound, no animation beyond the harbour swell, emoji placeholder art
- No tech or upgrade progression beyond building more sheds
- Nothing past the lighthouse — no endgame content after the win
- The archipelago/trade-route map (ships' origins, lanes, blockades) — only the
  harbour scene exists
