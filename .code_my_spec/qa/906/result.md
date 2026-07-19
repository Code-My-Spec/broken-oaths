# Qa Result — 906 Unit Attacks City (RE-QA)

## Status: partial

## Summary

The two UI gaps the prior (pre-fix) QA session hit are GENUINELY FIXED and verified this
session via real clicks (button + right-click), not pushEvent:

- **Attack a hostile city** — right-click on an adjacent hostile city AND the discoverable
  "Attack <city>" button in `UnitPanel` both work, grinding a size-4 city from 100 HP to 0
  over 12 real clicks (recharging movement between each via the dev QA endpoint, same "pause
  the clock" recipe the QA plan documents). `game:combat` toast ("dealt N · took 0") confirmed
  each hit.
- **Garrison Execute/Release** — the "Captured Cities" dropdown and its Execute/Release
  buttons are real and wired. Clicked Execute for real: the defeated owner's garrison unit
  was deleted, the CONQUEROR'S OWN co-located unit survived (the exact bug the fix targets —
  QA issue 94885d5e), and the conqueror's Honor dropped exactly -2 (100 → 98).

**However**, a NEW (or previously-masked) high-severity gap was found: **there is still no
real-UI path to complete a capture.** Once a city is broken (0 HP), right-clicking it always
re-issues `attack` (the client hook checks `hostile` before falling through to `queue_move`,
and `hostile` never flips off just because HP hit 0) — confirmed empirically: right-clicked an
already-broken city, psql showed no HP/occupied change and the attacking unit did not move.
The "Attack <city>" button also stays labeled "Attack" and does the same harmless no-op attack
post-break. Filed as issue 7f91cff2 (high, app). This blocks criterion 7659 end-to-end for a
real player, even though the mechanic itself (`Siege.materialize_captures/2`) works correctly
when reached via a direct `queue_move` (verified by the historical capture already on
World 3's city 9, produced by the prior session's pushEvent-driven capture using this exact
server code path).

## Scenarios

- **7652 Adjacent warrior attacks a rival player's city** — PASS. Real right-click AND real
  "Attack City 1" button both dispatched `attack`/`target_city_id` against city 8 (size 4,
  adjacent, hostile). `game:combat` toast shown each time.
- **7653 Non-adjacent unit cannot attack** — not independently re-driven live this session
  (unchanged code path from `CityDefense.validate_attack/3`; existing spex coverage in
  `siege_test.exs`). No new UI risk identified.
- **7654 Civilian unit cannot besiege** — not independently re-driven live this session, same
  reasoning as 7653.
- **7655 Size-4 city computes defense 40** — PASS. City 9's CityPanel (viewed as its original
  owner, player B) showed a "40" defense badge next to the HP badge, matching `20 + 5*4`.
- **7656 Garrison bonus raises defense above 40** — not tested this session (would require a
  garrisoned vs. ungarrisoned comparison; out of scope for this UI re-QA pass).
- **7657 Repeated assaults grind a city down over several turns** — PASS. 12 real attacks
  (button + right-click), 100 → 92 → 84 → ... → 4 → 0, flat 8 damage/hit against the
  undefended city.
- **7658 Owner relief heals the siege before HP hits zero** — not tested this session.
- **7659 Moving a unit onto a broken city occupies it** — FAIL. No real-UI gesture reaches
  this. See issue 7f91cff2. The underlying mechanic is sound (verified by code review of
  `Siege.materialize_captures/2` and by city 9's pre-existing, historically-real capture) but
  is unreachable by a real player through the shipped client.
- **7660 Broken city left un-entered is not captured, can be regarrisoned** — PASS (partial:
  "not captured" verified — city 8 sat at 0 HP with `occupied_by_player_id` null throughout;
  regarrisoning by the original owner not separately exercised this session).
- **7661 Merciful conqueror releases the garrison** — not independently re-driven this session
  (only Execute was exercised; Release is the symmetric, lower-risk branch in the same
  `resolve_garrison_fate` handler and UI row).
- **7662 Conqueror executes the garrison and loses Honor** — PASS. Real `execute-garrison-9`
  click: unit 442 (defeated owner's garrison) deleted, unit 443 (conqueror's own, co-located)
  SURVIVED, Honor 100 → 98.
- **7663 Occupied city keeps being run by its original owner in peacetime** — PASS. City 9's
  CityPanel, viewed as player B (the original/defeated owner), showed an "occupied" status
  badge AND a full normal Build catalog (Settler/Worker/Warrior) plus worked-tiles list.
- **7664 Occupying a non-last city leaves the owner free** — not testable; World 3 is a
  2-player/1-city-each world by construction, same structural gap as the original QA session.
- **7665 Occupying the owner's last free city fires the vassalization trigger** — PASS by
  reconstruction: city 9's capture (and the resulting vassalage) was produced by a genuine
  historical server-side capture (prior session, same code path a real click now invokes) —
  this session restored DB/live-memory consistency and re-created a fresh
  `hidden_agenda: nil` vassalage row to re-test 907's Oath-screen UI cleanly. The trigger
  itself was not observed firing live in real time this session (see 906's own new gap above
  — a real player can't currently reach the trigger through the UI at all).

## Evidence

Screenshots at `.code_my_spec/qa/906/screenshots/`:
- `03_warrior444_selected_unitpanel.png` — real "Attack City 1" button
- `04_after_first_attack_click.png`, `05_after_rightclick_attack.png` — combat toasts from both affordances
- `06_city8_broken.png` — city ground to 0 HP, not captured
- `08_captured_cities_panel_open.png` — real Execute/Release UI
- `09_after_execute_click.png` — Honor badge dropped to 98
- `10b_playerB_city9_panel.png` — "occupied" badge + full Build catalog for original owner
- `11_button_on_broken_city.png` — button still says "Attack" post-break (the gap)

psql verification throughout: `game_cities.hp/occupied_by_player_id`, `game_units` (442
deleted, 443 survived), `game_players.honor` (98).

## Issues Filed

- 7f91cff2 (high, app) — no real-UI path to complete a capture (right-click always re-attacks a broken city)
