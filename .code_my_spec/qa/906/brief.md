# Qa Story Brief — 906 Unit Attacks City (RE-QA #2 — verifying the Move In fix)

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) for state verification + dev QA control surface (`/dev/qa/worlds/3/...`) for staging.

## Auth

Two pre-seeded QA accounts, password `qa-password-123!` for both:

- Player A (lord/original owner of city 8): `qa-901-a@broken-oaths.test` — player_id 11
- Player B (vassal/original owner of city 9): `qa-901-b@broken-oaths.test` — player_id 12

Login via `#login_form_password` at `http://localhost:4050/users/log-in`. Log out via `a[href='/users/log-out']` (DELETE link) to switch identities cleanly (ends Presence tracking so the other player reads as offline).

## Seeds

World 3, already paused at turn 317 going in. Prior sessions left city 8 (player 11's own city) ground down to 0 HP, not yet captured, with player 12's warrior 444 sitting adjacent (tile 504) — the exact "broken hostile city, attacker adjacent" state needed to test the previously-missing capture-completion affordance (issue 7f91cff2, now marked resolved).

## What To Test

- Log in as player B. Recharge unit 444's movement (`PATCH /dev/qa/worlds/3/units/444 -d recharge=true`).
- Aim the canvas camera at tile 504 (grid-search yaw/pitch for max `depth` via `GlobeRender.rot/depth`, since the default camera doesn't face the enemy front) and left-click select warrior 444.
- Confirm the UnitPanel now renders a `move-in-city-8` button labeled "Move In City 1" (not "Attack") once the target city is `broken`.
- Click it for real. Verify via psql: `game_cities.occupied_by_player_id` for id 8 is now 12, unit 444's own `tile_id` moved onto 505 (the city's tile) — a genuine movement-triggered capture.
- Open the "Captured Cities" panel (`data-test="captured-cities-panel"`) and confirm city 8 lists with no fallen-garrison choice (no living defender was on the tile).
- Since city 8 was player 11's ONLY city, expect a FRESH reciprocal `Vassalage` row (lord=12, vassal=11) to fire live — log in as player A and confirm the "Terms of Oath" modal appears unprompted.

## Result Path

Findings filed via `create_issue`, verdict via `submit_qa_result` (task_id `6daa4700-fa70-401e-a5db-4043ad072f88`). Screenshots at `.code_my_spec/qa/906/screenshots/` (prefixed `re2_`).

## Setup Notes

Completing this particular capture (player 12 taking player 11's last city) creates a reciprocal vassalage on top of the pre-existing lord=11/vassal=12 relationship — both relationships coexist independently (DB unique constraint is per-vassal-slot, not per-player), and this was accepted deliberately as bonus live evidence for 907's trigger rather than avoided. Criterion 7664 (occupying a non-last city leaves the owner free) remains untestable within World 3's fixed 1-city-per-player starting layout without founding a third city specifically for that purpose — noted as a gap, not worked around.
