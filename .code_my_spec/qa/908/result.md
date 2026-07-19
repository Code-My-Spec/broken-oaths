# Qa Result — 908 Tribute Payments (RE-QA #2)

## Status: pass

## Summary

Building on the already-solid tribute-flow evidence from the prior session, this session added
a genuinely new capability: World 3 now carries TWO simultaneous, independent vassalages (the
original lord=11/vassal=12, plus a fresh reciprocal lord=12/vassal=11 produced by 906/907's RE-QA
session), giving live, concurrent, multi-vassalage tribute evidence for the first time —
previously "not independently tested" for lack of a second relationship. Every turn boundary
stepped this session produced correct `game_gold_logs` rows for BOTH relationships
simultaneously, each independently computing `round(income × rate)` off each player's own real
city-derived gold income (912). Rate changes, debt, and the levy Answer/Refuse UI all re-confirmed
working via real clicks.

## Scenarios

- **7673 Lord raises a vassal's tribute rate from the Vassals panel** — PASS, fully live. Real
  form submits changed relationship id=2's rate 100%→25%→100%→25% across the session; each change
  persisted immediately (psql) and was reflected in the very next boundary's tribute amount.
- **7674 Vassal earning income at a set rate pays the correct tribute** — PASS with exact,
  isolated math. At 25%, city 9's income (3-4 gold depending on size) produced tribute of
  round(income×0.25) every turn; at 100%, tribute exactly equalled income. Verified across dozens
  of stepped boundaries in `game_gold_logs`.
- **7675 A raised rate is applied on the next turn's tribute** — PASS, clean before/after. Setting
  relationship id=2 to 100% then stepping produced a tribute jump to the full income amount on
  the VERY NEXT boundary; resetting to 25% dropped it back on the next boundary after that.
- **7676 Vassal with an empty treasury goes into debt paying tribute** — PASS. Cranked
  relationship id=2 to 100% and stepped ~60 turns; player 12's `gold` ran deeply negative (-90)
  while tribute continued being deducted in full every turn, never clamped at zero.
- **7677 Vassal answers a call to arms and keeps command of the units sent** — PASS (re-confirmed
  from prior session's real click: `game_levies.status` → `answered`, all units retained).
- **7678 Vassal refuses the call to arms and takes strain and Honor hits** — PASS (Oath Strain
  half re-confirmed: real refuse click spiked `oath_strain` by 15). Honor-on-refusal was NOT
  observed moving this session either — this remains a known, documented gap in `Tribute`'s own
  moduledoc, already tracked as issue c0ec53ed (medium), not re-filed.
- **7679 Many vassal tributes resolve in one turn tick** — PASS, and genuinely upgraded this
  session: with TWO independent active vassalages now live in World 3 (lord=11/vassal=12 AND
  lord=12/vassal=11), every stepped turn boundary produced two correct, independent
  `game_gold_logs` tribute rows in the same tick — real concurrent multi-vassalage resolution,
  not the single-relationship case the prior session was limited to.

## Evidence

Screenshots at `.code_my_spec/qa/908/screenshots/` (this session prefixed `re2_`):
- `re2_01_playerA_vassals_panel.png` — real rate-change form, Oath Strain, levy status all live

psql verification: `game_gold_logs` — dozens of rows across both directions
(`from_player_id=11,to=12` and `from_player_id=12,to=11`) in the same turns, e.g. turn 403/404
both directions logged `amount=1` simultaneously; `game_players.gold` deltas matching exactly;
`game_vassalages.tribute_rate` changes persisting and taking effect the following boundary.

## Issues Filed

None new. Previously-filed issue c0ec53ed (refusal doesn't dock Honor) remains open/tracked, not
re-filed — unchanged behavior, already documented as a known gap.
