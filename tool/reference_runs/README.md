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

| file | charters | diff | won | notes |
| --- | --- | --- | --- | --- |
| `human-2026-08-16-full_purse-poor_soil.pa1` | a_full_purse, poor_soil | 1 | day 93, pop 40 | first complete human trace. No merchant hired, no dark trade at all. |

These are gameplay numbers only — no name, no email, no device id. See
`lib/sim/run_code.dart` for what the format can and cannot carry.
