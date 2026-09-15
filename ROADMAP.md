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

**Diagnose the Grange outlier.** Under *A Grander Light*, one seed of eight
blew out to 351 days against a baseline maximum of 133. The median improved
clearly, so the route ships, but a result that bad on one seed is not noise and
has not been explained.

**Close the bot's income gap.** `tool/calibrate.dart` puts the balance bot
28.5% off a real player's curve, and nearly all of what remains is coin — it
still earns far less than a person does. Officer hiring cannot be turned on in
the bot until that closes, because wages are permanent and its economy cannot
carry them. Until then, every number the probe reports is measured against a
player who earns too little.

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

**Pets, with trade-offs.** *Comes after animals and husbandry* — two of the four
below have nothing to attach to until livestock exists.

A ship arrives, rarely, with animals aboard, and you can buy one. Every pet
lifts happiness; each then helps one part of the port and costs another, so it
is a choice about the run you are having rather than an upgrade you take because
it is there.

The fiction that holds it together: **the port's attention is finite.** Where
the animal lives gets better, and somewhere else gets neglected.

| | Helps | Costs | Why |
| --- | --- | --- | --- |
| **Dog** | Livestock yield | Ore | Works the grange; will not follow anyone down a shaft |
| **Bird** | Ore | Grain | A caged bird reads the bad air; it also eats the seed |
| **Cat** | Goods kept in store | Livestock yield | Kills the rats in the warehouse, and hunts the poultry too |
| **Monkey** | Prize booty | Goods kept in store | Nimble on a boarded hull, and pilfers your own stores |

Dog and bird are direct opposites on ore; cat and monkey are direct opposites on
stores. Every pet is somebody's problem, and the monkey gives the dark trade a
reason to want one.

Four things to get right:

- **The rarity must not become a gacha.** Rolling for *which* animal turns four
  species into a collection to reroll for, and a rare drop you can chase is the
  slot machine this game keeps refusing. The fix is to split the two: let the
  **encounter** be rare and the **species be your pick**. The surprise survives,
  the chase never starts.
- **Both halves visible before you pay.** A cost you discover afterwards is a
  trap, not a trade-off.
- **Voyages stay untouchable.** A pet may follow the captain's rule — better
  terms for voyages sent *from now on* — but nothing may move a hull already at
  sea. That is asserted at
  [trade_test.dart:184](test/trade_test.dart#L184).
- **Earned or bought with coin, never sold for money.** Cosmetics for sale are
  on the list at the bottom of this file, and a pet is exactly the sort of
  harmless-looking thing a store gets introduced through.

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
