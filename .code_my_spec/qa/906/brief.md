# Qa Story Brief — 906 Unit Attacks City (RE-QA)

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) for state verification + dev QA control surface (`/dev/qa/worlds/3/...`) for staging.

## Auth

Two pre-seeded QA accounts, password `qa-password-123!` for both:

- Player A (attacker/future lord): `qa-901-a@broken-oaths.test` — player_id 11
- Player B (defender/future vassal): `qa-901-b@broken-oaths.test` — player_id 12

Login via `#login_form_password` at `http://localhost:4050/users/log-in` (fields `input[name="user[email]"]`, `input[name="user[password]"]`, submit button `.btn-primary`). Switch identities with `vibium cookies clear` between sessions.

## Seeds

World 3 ("QA World (Multiplayer)") — already paused (`turn 291`). Each player has one size-4 city: City 8 (player 11, tile 505), City 9 (player 12, tile 258).

**Re-QA state note:** City 9 was already captured by player 11 in the PRIOR (pre-fix) QA session, via the same server-side `attack`/movement code a real click invokes — that's live-authoritative in-memory `WorldServer` state that a raw SQL edit cannot reset (`captured_cities_visible_to` reads `state.cities`, not a fresh DB query — confirmed empirically: a DB-only reset left the "Captured (1)" badge still showing). Rather than fight that, this session:

- Restored city 9 to DB-consistent captured state (`hp=0, occupied_by_player_id=11`) matching live memory.
- Recreated a FRESH `game_vassalages` row (id 2: lord=11, vassal=12, tribute_rate=0.25, oath_strain=0, hidden_agenda=NULL) so the Oath screen is genuinely re-testable via a real click (907's brief covers this).
- Spawned unit 443 (player 11 warrior) onto city 9's tile 258, alongside the pre-existing unit 442 (player 12 warrior, spawned this session as the "fallen garrison") — this stages a clean, real Execute/Release test: a living defeated-owner unit AND a living conqueror unit co-located on the captured tile, exactly the state a genuine capture-by-move leaves behind.
- Spawned unit 441 (player 11 warrior, tile 259 — adjacent to city 9) as a spare/leftover from initial staging; not the primary attack demo (see below).
- Spawned unit 444 (player 12 warrior, tile 504 — adjacent to city 8, tile 505) — city 8 is player 11's ONLY city and was NEVER captured this session, so this is a genuinely fresh, uncaptured hostile-city target for the right-click/Attack-button demo. Grinding it to 0 HP does NOT capture it (capture requires a separate move-onto-tile order) — this avoids flipping player 11 into a circular vassal-of-12 relationship, which would contaminate the 907/908 lord=11/vassal=12 pairing under test.

## What To Test

- Log in as player B (`qa-901-b@broken-oaths.test`), navigate to `/play/3`.
- Left-click select warrior 444 (tile 504), confirm the UnitPanel renders an `attack-city-8` "Attack City 1" button (criterion 7652's discoverable-button half) since city 8 is adjacent and hostile.
- Right-click city 8's tile (505) directly (`board_click.sh 505 right` — the barbarian/camp-style attack gesture) AND separately click the `attack-city-8` button — confirm both dispatch the `"attack"`/`target_city_id` event and reduce city 8's HP (psql `game_cities.hp` for id 8), with `game:combat` push showing damage_dealt/damage_taken.
- Repeat (recharge warrior 444's movement via `PATCH /dev/qa/worlds/3/units/444 -d recharge=true` between clicks — the same "pause the clock, act repeatedly" recipe the QA plan documents) until city 8's HP reaches 0 — criterion 7657 (grind over several actions), 7655 (size-4 city defense), 7656 (garrison bonus, since city 8's own lord unit 212 sits nearby but not garrisoned inside — note whichever applies).
- Verify via psql that city 8 is `broken` (hp=0) but NOT captured (`occupied_by_player_id` still null) — criterion 7660 — since no move-onto-tile order was issued. Screenshot the board showing the broken city.
- Log in as player A. Confirm the top bar's "Captured Cities" panel (`data-test="captured-cities-panel"`) shows city 9 with a `fallen-garrison-choice` block (units 442 living, belongs to defeated owner 12) — criterion 7659's downstream state (already captured this session, see Seeds note) plus the REAL Execute/Release UI (previously missing — issue ffa66192, now fixed).
- Click `execute-garrison-9` (the real button, not pushEvent). Verify via psql:
  - Unit 442 (player 12's garrison) is deleted.
  - Unit 443 (player 11's own occupying unit, co-located on the same tile) SURVIVES — this is the exact bug (QA issue 94885d5e) the fix targets: Execute must never delete the conqueror's own army.
  - `game_players.honor` for player 11 drops by 2 (100 → 98) — criterion 7662.
- Verify city 9's CityPanel (as player B, its original owner) still shows an "occupied" status badge and a normal Build catalog — criterion 7663.
- Non-adjacent/civilian negative checks (criteria 7653, 7654) are unchanged regression surface already covered by `test/broken_oaths/game/siege_test.exs` and the spex files — not re-driven live this session (no new UI risk there; the fix was scoped to the attack/garrison-fate AFFORDANCE, not these validations).

## Result Path

Findings filed as issues via `create_issue`, final verdict submitted via `submit_qa_result` (task_id 77de6ac2-9715-4def-b751-2c067f49df74). Screenshots at `.code_my_spec/qa/906/screenshots/`.

## Setup Notes

World 3's 2-city/2-region cap means a single continuous "fresh right-click siege all the way through capture" demo for THIS SAME lord/vassal pair isn't reachable without re-contaminating 907/908's state (see Seeds note) — split into two clean sub-demos instead: (1) a genuinely fresh, real-click grind-to-broken on city 8 (proves the previously-missing attack affordance is real), and (2) a real-click Execute/Release resolution on city 9's already-captured state with freshly co-located units (proves the previously-missing garrison-fate affordance is real, and specifically re-verifies the execute-deletes-only-the-defeated-owner bug fix). Criteria 7664 (non-last-city capture leaves owner free) still requires a 3rd city/player, same gap as the original QA session — not exercised.
