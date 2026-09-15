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

## Next

**Animals and husbandry.** The second half of the Grange, and the obvious
extension of the route it opened. The Grange converts *time* into yield; herds
are the same bargain in a more literal form — stock that grows on its own if it
is fed and housed, and is worth nothing the week you buy it. Likely shape:
livestock as a slow-growing chain producing food and wool, with wool feeding
the existing weaver and a hide or dairy good giving the farm chain somewhere to
go. The point is to give the honest side depth without adding another thing to
click every few minutes.

**[The full plan is written up in design/livestock.md](design/livestock.md)** —
cows, sheep and chickens, plus a bakery; wool into sailcloth and tallow, cheese
and biscuit onto the lighthouse bill, so the chain is load-bearing rather than
optional. The animals earn in goods, not food: meat, milk and eggs exist only to
cancel the grain the herds eat, so they never become a second town competing for
the harvest. It also
records the two things that have to be fixed *before* any of it is built (food
is counted one unit per person-day, so meat would be strictly worse than fish;
and the balance probe never staffs a shed with no immediate output, which has
already wrecked two measurements), and the pass/fail bar agreed in advance.

**Diagnose the Grange outlier.** Under *A Grander Light*, one seed of eight
blew out to 351 days against a baseline maximum of 133. The median improved
clearly, so the route ships, but a result that bad on one seed is not noise and
has not been explained.

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

**Recalibrate the charters.** The difficulty budget does not match what the
charters actually cost. Measured: *Poor Soil* carries weight 1 and costs about
46 days; *Bitter Seas* carries weight 2 and cost about −1. The weights were set
by judgement and have never been re-derived from play.

**Measure the dark trade end to end.** Spice and the privateer captain have each
been measured on their own — spice at a quarter of a prize, the captain at
+22% odds and +55% booty. Whether the whole route now pays across a full run,
against the honest path, has not been measured once. That needs a played run
with the powder mill, the berth, and boardings actually happening.

**More life in the world.** Smoke that drifts on the wind, a ship that visibly
leaves the quay when you send a consignment, weather you can see arriving. The
world went from flat shapes to a populated port recently; this is the
remainder of that work, and it is polish rather than mechanics.

**A happiness system.** The port has people in it and they have no opinion. A
happiness reading would give the town a voice — responding to whether they are
fed well or merely fed, housed or crowded, worked in a port that runs sweetly or
one that lurches from crisis to crisis, and whether you are in the dark trade at
all. It should have teeth: unhappy hands work worse, newcomers stop arriving,
and a port run badly enough starts losing the people it has. Growth you can lose
is the pressure the honest route is currently missing — nothing on that side
pushes back once the chains are running.

The one rule it must hold to is the fourth row of the table in
[README.md](README.md): **no relief for sale.** Pressure is the point; a
*purchase* that makes the pressure go away is the pattern. Notoriety already
sets the shape, and sets it well: there is no bribe and no passive decay, but
there *is* a way down — honest commerce launders, and a clean inspection pays
back four points. The meter comes down through play. Happiness should answer the
same way: to feeding people properly, housing them, paying them, keeping the
port steady. Never to a payment, and never to simply waiting it out.

**Pets, with trade-offs.** *After animals and husbandry, which supplies the
meat.* A ship puts in around day 40-50 with animals aboard and you buy one —
the only pet the run will ever offer. Each lifts happiness, raises one product
and lowers another, and eats meat, so keeping one is an obligation as well as a
gift. Dog, cat, bird, monkey and turtle, arranged so that every product one
raises is another's cost: nothing is strictly best, and the pick is a read on
which lighthouse item you are behind on — which day 40-50 is exactly when you
first know.

**[The full plan is in design/pets.md](design/pets.md)**, including the numbers
to start from, why no pet may touch meat, and how a meat-fed pet avoids gating
one optional system behind another.

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
