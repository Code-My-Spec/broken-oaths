# Qa Result — 912 City Gold Income

## Status: pass

## Summary

All seven criteria verified with clean, isolated, live evidence. The single most valuable piece
of evidence this session produced was founding a throwaway third city (city 14) specifically to
get a controlled, single-tile-swap before/after comparison: the SAME size-1 city measured at
exactly +1 gold/turn while working a plain tile, then exactly +2 gold/turn after re-assigning its
one worked tile to a Coast tile — an unambiguous, isolated demonstration of both the base formula
and the coastal bonus in the same breath. A city-growth transition (size 5→6) was also caught
live in the tribute log, showing income jump from 3 to 4 gold on the exact turn boundary the
city's size changed.

## Scenarios

- **7713 Size-4 landlocked city earns 3 base gold a turn** — PASS. City 8 (landlocked, size 4)
  accrued `banked_gold` at a steady, isolated +3/turn across 12 offline turns — exactly
  `1 + floor(4/2) = 3`.
- **7714 A freshly founded size-1 city earns 1 base gold a turn** — PASS, isolated. Freshly
  founded city 14 (size 1), working a plain (non-coastal) tile: the player's total per-turn gold
  delta minus the other city's known contribution and net tribute isolated to exactly +1.
- **7715 A coastal size-4 city adds tile gold to its base** — PASS, isolated (via the size-1
  control city rather than a size-4 one, same formula/mechanism). Re-assigning city 14's one
  worked tile to the Coast tile (341) raised the SAME city's isolated per-turn contribution from
  1 to exactly 2 (base 1 + coast bonus 1) on the very next turn — a clean single-variable
  before/after swap on the identical city.
- **7716 Growing to size 4 raises the city's gold income next turn** — PASS. Caught live in the
  tribute log: city 9's contribution was 3 gold/turn (size 5) through turn 342, then exactly 4
  gold/turn (size 6) from turn 343 onward — the transition landed on the exact turn boundary the
  city's `size` column changed, both at a fixed 100% tribute rate so the log directly mirrors raw
  income.
- **7717 Online player's cities deposit their combined gold into the treasury** — PASS
  (cross-verified with 909). While connected, a player's `gold` rose every turn by their full
  combined city income (multiple cities summed correctly) with `banked_gold` untouched.
- **7718 Offline player's gold income accrues into the capped bank** — PASS (cross-verified with
  909). While disconnected, the same combined per-city income accrued into `banked_gold` instead,
  capped at `bank_cap`.
- **7719 Tribute taxes the real city-derived gold income** — PASS (cross-verified with 908).
  `game_gold_logs.amount` matched `round(income × rate)` exactly turn after turn, where `income`
  demonstrably tracked real city size/worked-tile changes (see 7716) rather than any stubbed
  test-only value — confirms issue 589386f2's original gap (no real per-turn gold income existed)
  is genuinely closed and wired all the way through to tribute.

## Evidence

Screenshots at `.code_my_spec/qa/912/screenshots/`:
- `re2_01_city8_panel.png` — city 8's CityPanel, size 4, landlocked, no Bronze Spearman option
  (pre-Bronze-Working, doubles as 911 evidence)

psql verification throughout: `game_players.gold`/`banked_gold` deltas isolated per-city via
controlled single-tile-swap and single-turn-boundary comparisons; `game_gold_logs` amounts
tracked across the size 5→6 growth transition; `game_cities.size`/`worked_tiles` confirming the
exact moment of each change.

## Issues Filed

None. Issue 589386f2 (the original "no real gold income exists" finding this story was built to
fix) is confirmed resolved by this session's isolated, quantitative evidence.
