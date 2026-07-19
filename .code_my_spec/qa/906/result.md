# Qa Result — 906 Unit Attacks City (RE-QA #2)

## Status: pass

## Summary

The high-severity gap from the prior two sessions (issue 7f91cff2 — no real-UI path to complete
a capture) is GENUINELY FIXED and verified via a real button click. Selecting warrior 444
(player 12) adjacent to player 11's broken city 8 now renders a `move-in-city-8` button labeled
"Move In City 1" (not "Attack") in the UnitPanel. Clicking it dispatched `queue_move` and
completed a real, movement-triggered capture: `game_cities.occupied_by_player_id` flipped to 12,
and the attacking unit physically moved onto the city's own tile (505) — confirmed via psql,
not reconstruction. The "Captured Cities" panel correctly showed the new capture with no
fallen-garrison prompt (no living defender was present). Since city 8 was player 11's only city,
a fresh reciprocal vassalization fired live in the same session (see 907's result) — bonus
confirmation that the capture→vassalize pipeline is wired end-to-end through the real client now,
not just reachable via `pushEvent`.

## Scenarios

- **7652 Adjacent warrior attacks a rival player's city** — PASS (re-confirmed from prior
  session's real button/right-click evidence; unchanged this session).
- **7653 Non-adjacent unit cannot attack** — not re-driven live; unchanged code path, existing
  spex coverage.
- **7654 Civilian unit cannot besiege** — not re-driven live; unchanged code path.
- **7655 Size-4 city computes defense 40** — PASS (re-confirmed, unchanged).
- **7656 Garrison bonus raises defense above 40** — not independently re-tested this session.
- **7657 Repeated assaults grind a city down** — PASS (re-confirmed from prior session).
- **7658 Owner relief heals the siege** — not tested this session.
- **7659 Moving a unit onto a broken city occupies it** — PASS. Real "Move In City 1" button
  click on warrior 444 against broken city 8 set `occupied_by_player_id=12` and moved the unit
  onto tile 505. This is the criterion the prior two sessions could not close — now closed.
- **7660 Broken city left un-entered is not captured, can be regarrisoned** — PASS (re-confirmed
  from prior session; city 8 sat broken/uncaptured for two full sessions before this one).
- **7661 Merciful conqueror releases the garrison** — not independently re-driven this session
  (city 8 had no living garrison to release; Release itself was verified in the original 906
  session on city 9).
- **7662 Conqueror executes the garrison and loses Honor** — PASS (re-confirmed from prior
  session's real click evidence: unit deleted, conqueror's own unit survived, Honor -2).
- **7663 Occupied city keeps being run by its original owner in peacetime** — PASS (re-confirmed;
  city 9's CityPanel still shows full Build catalog for its original owner, player B).
- **7664 Occupying a non-last city leaves the owner free** — still not testable inside World 3's
  fixed 1-city-per-player starting layout without founding a dedicated third city solely for this
  purpose; noted as a genuine coverage gap, not worked around.
- **7665 Occupying the owner's last free city fires the vassalization trigger** — PASS, and this
  session produced completely FRESH live evidence (not reconstructed): capturing city 8 via the
  real Move In button immediately created a new `game_vassalages` row and the Oath screen fired
  live for player 11 on their next page load. See 907's result for the full trace.

## Evidence

Screenshots at `.code_my_spec/qa/906/screenshots/` (this session prefixed `re2_`):
- `re2_03_unit444_selected.png` — real UnitPanel with the "Move In City 1" button (data-test
  `move-in-city-8`), replacing "Attack" once the target city is broken
- `re2_04_city8_captured_via_move_in_button.png` — board immediately after the click; top bar now
  shows "Vassals (1)" and "Captured (1)" for player 12
- `re2_05_captured_cities_panel.png` — Captured Cities panel showing city 8, "Secured — no living
  defenders remain"

psql verification: `game_cities` (id 8: `occupied_by_player_id` 11→null→12 across the session,
`hp=0` throughout), `game_units` (unit 444's `tile_id` 504→505), `game_vassalages` (new row id 3:
lord=12, vassal=11, fresh defaults).

## Issues Filed

None new. The previously-filed issue 7f91cff2 (no real-UI capture-completion path) is confirmed
resolved by this session's live evidence.
