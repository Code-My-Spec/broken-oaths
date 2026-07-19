# Qa Story Brief — 912 City Gold Income

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) + dev QA control surface
(`/dev/qa/worlds/3/step`, `/dev/qa/worlds/3/units` for a throwaway settler).

## Auth

- Player A: `qa-901-a@broken-oaths.test` / `qa-password-123!` — player_id 11
- Player B: `qa-901-b@broken-oaths.test` / `qa-password-123!` — player_id 12

## Seeds

World 3. Neither existing city (8 or 9) has a Coast tile in its territory (both are landlocked),
so a throwaway third city was founded near a known coast tile (id 341, city 14 at tile 342) purely
to isolate the coastal-gold-bonus criterion.

## What To Test

- Isolate a single player's OWN city gold income from tribute noise by tracking `game_gold_logs`
  alongside `game_players.gold`/`banked_gold` deltas each stepped turn — tribute nets are visible
  and subtractable turn-by-turn.
- Landlocked size-4 city: confirm steady +3/turn accrual (offline, isolates `banked_gold`) matches
  `1 + floor(4/2) = 3` — 7713.
- Fresh size-1 city (city 14), working a NON-coastal tile: step one turn, isolate the delta after
  subtracting the other city's known contribution and net tribute — confirm exactly +1 — 7714.
- Same city 14, re-assign its one worked tile to the coastal tile (341): step one turn, confirm
  the isolated delta rises to exactly +2 (base 1 + coast bonus 1) — 7715.
- Growing city: track a size transition (5→6) across a turn boundary via tribute-log amounts
  (which mirror the vassal's raw income 1:1 at 100% rate) — confirm the amount jumps from 3 to 4
  exactly at the boundary the city's `size` column changes — 7716.
- Online vs offline treasury/bank split — already the mechanism 909 verifies; cross-reference here
  as confirmation this income is the SAME real value feeding both systems — 7717, 7718.
- Tribute basis — cross-reference 908's gold_logs: confirm `amount = round(income × rate)` where
  `income` is this story's own real per-city sum, not a stubbed/test-only value — 7719.

## Result Path

Findings filed via `create_issue`, verdict via `submit_qa_result` (task_id
`851e011c-cd09-485e-a722-dcbd97e22f48`). Screenshots at `.code_my_spec/qa/912/screenshots/`.

## Setup Notes

Founding a throwaway third city (city 14) to reach a coastal tile was necessary since neither
pre-existing city in World 3 has Coast in its territory — this is a deliberate, minimal
scenario-construction step (not a workaround for a missing feature), and was reverted to the
non-coastal control state after the coastal measurement for a clean before/after comparison of
the SAME city.
