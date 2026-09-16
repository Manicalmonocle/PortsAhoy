# Reference runs

Real runs, played by a person, kept so the balance bot can be checked against
something other than its own opinion.

`tool/balance_probe.dart` is the only thing that tests a balance change across
more than one seed, and it has been wrong every time it was checked: it never
sent a consignment, it underestimated early income by ~40%, and — measured
against the first complete human run below — it takes 50 days longer to win the
same game.

Decode one with:

```sh
dart run tool/decode_run_report.dart tool/reference_runs/<file>.pa1
```

| file | charters | diff | won | kind | notes |
| --- | --- | --- | --- | --- | --- |
| `human-2026-08-16-full_purse-poor_soil.pa1` | a_full_purse, poor_soil | 1 | day 93, pop 40 | straight | first complete human trace. No merchant hired, no dark trade at all. |
| `human-2026-09-13-dark-full-chain-diff4.pa1` | + full_nets, a_grander_light, swift_hulls, rich_contracts | 4 | day 126, pop 51 | straight | **first real dark-trade trace.** Full chain by day 74, five hulls boarded, ~17 spice total — and the same win day as the run before it without the chain. Net zero. The baseline any spice retune is measured against. |
| `human-2026-09-15-honest-80d.pa1` | none | 0 | day 80, pop 37 | straight | pure honest run on 1.6.1-29. Built none of the four dark sheds though all were unlocked, and hired no quartermaster on a build that still offered one. Food sat on the growth gate for the last twenty days. |
| `human-2026-09-15-full-purse-78d.pa1` | a_full_purse | 0 | day 78, pop 37 | straight | grange up on **day 16**, which is what showed the probe was building it twenty days too late. Finished 2 tools spare against 80 needed and 160 sailcloth against 90. |
| `human-2026-09-16-dark-prize-88d.pa1` | none | 0 | day 88, pop 38 | **probing** | deliberately unequipped: berth from day 57 but no privateer captain ever hired, no distillery, no bonded cellar, one boarding in thirty-one days. Also shipped its own food away on day 73 and starved for five days, losing five people — a test of whether a run survives a bad decision. It does. Not a verdict on the dark trade. |

## Played straight, or played to break it

**Not every run here is someone trying to win.** Some are deliberate stress
tests — the player probing for bugs and exploits, and checking a run is still
winnable after a bad decision. Those traces are valuable for exactly that, and
are the wrong thing to tune balance against or calibrate the bot to: a run that
deliberately ships its own larder away is not evidence about how the game paces.

The `kind` column says which is which. Read it before drawing a conclusion from
a day count.

These are gameplay numbers only — no name, no email, no device id. See
`lib/sim/run_code.dart` for what the format can and cannot carry.
