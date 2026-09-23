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

**Decide the dark trade — keep it, or cut it.** It has been reworked three
times and has never once been measured on a policy that could actually play it.
1.14 fixed the last two things standing in the way: the berth is priced in
barrels instead of rope, so entering the route no longer subtracts from the
bill; and spice now buys what the port is *short of* rather than whatever a
trader felt like offering. What is missing is a played run under those terms.
If it still is not worth the hands when the payoff finally lands on the right
goods, cutting it is the honest answer and the game loses nothing it needs.

**Teach the probe to trade spice, and stop it committing on day ten.** The
blocker on the item above, and the longest-standing hole in this project's
measurements. The probe has never taken a spice deal — 0 of 47,699 seen —
because it never crews a bonded cellar, which scores zero on
margin-per-worker-tick like every other shed whose output is not immediate. Its
dark policy also builds a cooperage, a berth and a powder mill before its second
sawmill, which no player would. Its dark median of 282 days against 77 honest is
therefore not evidence of anything, and **no further dark-trade balance change
should be made until it is.** This is the same error for the fourth time — the
grange that never ripened, the berth that never got built, the cellar that never
got crewed. The measurement keeps measuring the policy rather than the mechanic.

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

**Measure the dark trade end to end.** First played attempt is in —
`human-2026-09-16-dark-prize-88d.pa1`, build 1.9.1+36, no charters, won on day
88 against 78 and 80 for the two honest runs on record. But it is not the
measurement this item wants:

- **One prize, in thirty-one days of owning a berth.** Built day 57, boarded
  once on day 65 for 41 tons and 10 spice.
- **No privateer captain was ever hired**, though the berth was up from day 57
  and the retinue took a third captain on day 80 instead. So the +22% odds and
  +55% booty never applied.
- **No distillery and no bonded cellar**, so the contraband-production half of
  the route was never built at all.
- A five-day famine on days 73-77 cost five people and muddies the day count.

That one boarding per month turned out to be reproducible, and the cause is now
known. With the berth actually standing, **13,661 blocked boardings were every
one of them for want of powder** — no other reason appeared. Powder cost is down
from 8 to 4, and the berth no longer eats rope and sailcloth, which it consumed
faster than the lighthouse asks for.

**A played run has now beaten the honest path with it** —
`human-2026-09-17-dark-77d.pa1`, 77 days against 78 and 80, the fastest trace on
record. Three prizes in thirteen days of holding a berth, where the same player
on the previous build got one in thirty-one, and the first privateer captain
ever hired. One run and one seed, so not a verdict — but the powder change is
doing what it was meant to.

**The probe still says the route loses** — 102 against 80 when this was
written, 282 against 77 at 1.14. And the measurement still has a hole in it big
enough to invalidate the verdict:

> **The probe has never taken a spice deal.** 0 taken, across every dark run
> ever measured — 6,044 deals seen when this was written, 47,699 by 1.14.

Spice exists because coin was never the constraint — it is the one thing that
converts risk into *finished goods*, which is what the lighthouse actually
wants. A dark run that never trades spice is measuring the chain with its payoff
removed. **That work has moved to "Next" above, along with the decision it
blocks.**

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
