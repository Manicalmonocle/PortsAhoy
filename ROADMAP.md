# Roadmap

What is intended next, roughly in order of confidence. **No dates**, on purpose:
this is one person's side project and a date would be a guess dressed up as a
promise.

Things move between these lists as they are measured. Several features in the
game shipped, measured badly, and were reworked or cut — that is the normal
course here rather than a mishap, so treat everything below "Next" as a
direction rather than a commitment. What the game already does is described in
[README.md](README.md); what it does *not* do yet is in
[What is not built yet](README.md#what-is-not-built-yet).

---

## Just shipped — 1.14, the livestock update

The three items that stood at the top of this file are built and live, and are
described properly in [README.md](README.md). In a line each:

- **Animals and husbandry.** Pasture, byre, hen house and bakery, all of them
  eating grain. Wool into sailcloth, cheese onto the bill, and a fourth retinue
  track — the reeve — that ripens them faster.
- **A happiness system.** The town has an opinion and it has teeth: growth runs
  0.8x to 1.5x with it, a day's work swings ±15%, and below 0.30 nobody new
  arrives at all. It answers to feeding, housing and paying people. Never to a
  payment.
- **Pets, with trade-offs.** One ship, day 40-50, five animals, +10%/-7%, and a
  meat bill for as long as you keep one.

Both plans are kept as they were written —
[design/livestock.md](design/livestock.md) and [design/pets.md](design/pets.md)
— including the numbers that were wrong the first time and what they measured
at.

---

## Next

**~~Decide the dark trade~~ — it stays.** Settled on 2026-10-06 by a played
run, `human-2026-10-06-dark-102d.pa1`, on build 1.14.1 with no charters: the
light lit on **day 102** against 77-88 for the honest runs on record. The route
costs real time, it is survivable, and the player's own verdict was that it
"definitely made it a little difficult. Which is a good thing."

The run is also the first that exercised the chain end to end, and the way it
went wrong is the best argument for keeping it. Cooperage day 50, powder mill
53, berth 75, three prizes on days 76, 80 and 83 carrying 12, then 24, then 41
spice — and the **bonded cellar not until day 98**. So concealment was zero for
every one of the twenty-two days the port held contraband, and all of it was
taken: "wasn't able to trade any spice because I kept getting boarded. Really
made the dark trade feel very piratey." Not one barter was recorded in a run
that took three prizes.

That is a mechanic teaching a lesson, and it is deliberately **not** being
signposted. A standing "you are holding unhidden contraband" readout was
offered and declined: "I think it's a good lesson. Need to have some aspects
not a little hidden." The cutter card still warns when one is actually
alongside, and the sheds panel still carries the Exposed/Hidden figures.

Worth noting what the same run says about the honest side, because it may be
the larger half of those 102 days: it finished holding **220 tools against a
bill of 80, 257 sailcloth against 70, and 88 cheese against 30**, with coin the
last thing it was waiting on. Three times the sailcloth the lighthouse asked
for is a sawmill-and-smithy story, not a piracy one.

**~~Teach the probe to trade spice~~ — abandoned, and the attempt is the
finding.** It was tried on 2026-10-05 and rolled back whole; none of it is in
the code. The spice-trading half turned out to be already done, and five
iterations of fixing the dark policy found four more faults behind it:

- the powder mill was never crewed (1.43 a worker-tick against a smithy's 2.9,
  and both eat ore, so the loser also trips the input test) — every one of
  47,269 blocked boardings read "Needs 4 powder";
- nor was the cooperage, and that one generalises: **barrels are a building
  material, so a margin ranking cannot see the shed that makes them**;
- barrels that were made got sold the day they were coopered;
- **only the first nineteen entries of any build order are ever built.**
  Reactive roofs take the rest of the 25-shed cap, so everything past
  'import_berth' in the honest order has never once executed — it builds one
  mine and one smithy, not the two it lists.

Each fix exposed the next binding constraint, and the best dark figure reached
was still ~116 days with the cellar often unbuilt and 0-1 spice deals taken. A
fixed list plus a hard shed cap plus reactive roofs cannot express a port that
also runs a dark chain; making it would mean a needs-driven build queue, which
would move the honest control as well — and the control is the only calibrated
thing here.

So the probe is not the instrument for this, and a played run answered in one
sitting what it could not answer in five rewrites. Worth remembering before the
next subsystem gets measured this way.

**~~Diagnose the Grange outlier~~ — probably explained.** Under *A Grander
Light*, one seed of eight blew out to 351 days against a baseline maximum of
133, and it had never been accounted for. A grange ceiling sweep reproduced the
same shape on ordinary seeds, and the tail scaled *inversely* with the bonus —
worst case 94 days at a 0.35 ceiling, 216 at 0.28, 302 at 0.20. That is a
payback failure, not variance: a grange is 400 coin and two hands committed
before it returns anything, so when the payoff drops the investment strands on
unlucky seeds. Shortening the ramp from 35 days to 24 took the worst case back
to 101. Worth confirming directly against *A Grander Light* before this is
called closed.

**Trim the probe's food surplus.** The bot carries twenty days of food where a
real run sat on the two-day gate for its final third, which means hands on a
fishing wharf nobody needed — hands not making planks. Worth fixing as an
efficiency, though it no longer blocks the livestock work: that chain is
designed to be food-neutral, so there is no food benefit for a comfortable bot
to be blind to.

*Largely resolved:* the bot's pacing gap was a housing bug, not an income
problem. Houses arrived only at fixed slots in the build order, so the port grew
into its cap and waited — seventeen days a run with every roof taken. Building
one the moment the town is short took the median from **96 days to 82**, within
two of the player it is calibrated against. The same measurement settled officer
hiring: it is still worse (90 against 82), but because wages crowd out houses
rather than because the bot is poor.

---

## Planned

**Recalibrate the charter weights.** *Half of this shipped in 1.14:* every
offer now guarantees at least one hardship and one advantage, after a player
drew three advantages and had no way to pay for any of them — an 8.2% hand from
a flat draw. What is still open is the budget itself.

The difficulty budget does not match what the charters actually cost.
Measured: *Poor Soil* carries weight 1 and costs about 46 days; *Bitter Seas*
carries weight 2 and cost about −1. The weights were set by judgement and have
never been re-derived from play.

**~~Measure the dark trade end to end~~ — done, by playing it.** See the
verdict under *Next*. Four played runs got it there, and the history is worth
keeping because three of them each measured something different:

- `human-2026-09-16-dark-prize-88d.pa1` — one prize in thirty-one days of
  owning a berth, no privateer captain ever hired, no distillery and no cellar.
  The cause turned out to be powder: with the berth standing, **13,661 blocked
  boardings were every one of them for want of a charge.** Powder cost went
  from 8 to 4.
- `human-2026-09-17-dark-77d.pa1` — 77 days against 78 and 80 honest, the
  fastest trace on record at the time. Three prizes in thirteen days and the
  first privateer captain ever hired.
- `human-2026-09-18-dark-early-88d.pa1` — committing early, and the run that
  produced "by the time you get your main things online for the lighthouse it's
  end game and hard to pivot". The berth stopped costing rope and sailcloth
  because of it.
- `human-2026-10-06-dark-102d.pa1` — the whole chain, and the verdict.

The probe never contributed a valid figure to any of this. That is written up
under *Next* as well, because it is the more useful lesson.

**More life in the world.** Smoke that drifts on the wind, a ship that visibly
leaves the quay when you send a consignment, weather you can see arriving. The
world went from flat shapes to a populated port recently; this is the
remainder of that work, and it is polish rather than mechanics.

**The boot screen.** It is a blue field with the game's name on it, and it
should carry the ManicalGaming name and logo. The web slot is already wired —
drop a file in at `web/icons/manical-logo.png` and it appears — and the Android
splash needs its own drawable.

**Play Store release.** The build side is done — signed AAB, privacy policy,
version stamping. What is left is paperwork and people: the $25 registration,
identity verification, store listing assets, the Data Safety declaration, the
IARC content rating, and twelve testers running a closed track for fourteen
unbroken days.

---

## Considering

These are ideas with a case for them, not commitments.

**A contracts route.** The honest mirror of the dark trade: standing orders from
the Admiralty that pay a premium and build reputation, where the dark trade
builds notoriety. Designed in some detail and set aside in favour of the Grange;
it would give the honest side a second branch, and it reuses the consignment
machinery almost entirely.

**The archipelago map.** Ships' origins, the lanes between ports, blockades.
Only the harbour scene exists — the destinations are currently three names and
a set of prices.

**Desktop, and possibly Steam.** Parked deliberately. The game is phone-shaped —
touch gestures, a narrow layout — and a desktop build needs mouse and keyboard
handling, a wider layout, and a Windows toolchain that does not exist on the
development machine. Steam also wants $100 per app and about five weeks of
waiting. Mobile first; this is a port, if it happens at all.

**Sound.** There is none. It is a real gap and not a hard one, but it is the
sort of thing that is easy to do badly.

---

## Not planned, ever

These are not "not yet". They are the reason the game is built the way it is,
and they are enforced by tests rather than by intention — see the table at the
top of [README.md](README.md).

- No ads, of any kind.
- No in-app purchases, no currency, no cosmetics for sale.
- No energy meters, no lives, no timers to wait out.
- **Nothing that shortens a duration for money.** Voyages are the only thing in
  the game that takes time, and no coin, item, building or action touches one.
- No silent telemetry. The one thing that can leave your device is a run report
  you choose to send, which carries numbers and nothing else — see
  [the privacy policy](https://manicalmonocle.github.io/PortsAhoy/privacy.html).
