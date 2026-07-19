# Qa Story Brief — 906 Unit Attacks City

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) for state verification + dev QA control surface (`/dev/qa/worlds/3/...`) for staging.

## Auth

Two pre-seeded QA accounts from `priv/repo/qa_seeds_multiplayer.exs`, password `qa-password-123!` for both:

- Player A (attacker/future lord): `qa-901-a@broken-oaths.test` — player_id 11
- Player B (defender/future vassal): `qa-901-b@broken-oaths.test` — player_id 12

Login via `#login_form_password` at `http://localhost:4050/users/log-in`. Switch identities with `vibium cookies clear` between sessions (both accounts cannot be logged in at once in one browser profile).

## Seeds

World 3 ("QA World (Multiplayer)", frequency 8, 2 spawnable regions) already exists from `priv/repo/qa_seeds_multiplayer.exs`. Each player has exactly one size-4 city:

- City 8 (player 11) — tile 505
- City 9 (player 12) — tile 258

No re-seed needed; verified live state via `psql broken_oaths_dev`.

## What To Test

- Pause the world first: `curl -X POST http://localhost:4050/dev/qa/worlds/3/pause`.
- Compute true hex adjacency for city B's tile (258) by logging in as player B and reading the Board LiveView hook's known-tile coordinates (`hook.tileById`), then finding the 6 nearest tile centers by 3D distance — confirmed candidates: 101, 106, 257, 259, 265, 266.
- Relocate player A's warrior (unit 376) onto an adjacent land tile (259) via `PATCH /dev/qa/worlds/3/units/376 -d tile_id=259`, then recharge movement (`-d recharge=true`).
- Attempt to attack city B (id 9) through the normal game board (left-click select, right-click adjacent hostile) — expected per acceptance criterion 7652 to find an "Attack" affordance. **Actual: none exists** (see Setup Notes / filed issues).
- As a workaround to still exercise the server-side mechanic, drive the LiveView Board hook directly via `vibium eval` (`hook.pushEvent("attack", {unit_id: 376, target_city_id: 9})`), which is the exact event payload the missing UI would send.
- Repeat the attack (recharge + pushEvent) and verify via psql (`game_cities.hp`) that the city grinds down over multiple hits — check the size-4 city's computed defense (expect 40 per criterion 7655) and that the warrior takes 0 counter-damage while the city is undefended.
- Once city HP reaches 0, verify via psql it is "broken" but NOT captured (`occupied_by_player_id` still null) — criterion 7660.
- Move warrior 376 onto tile 258 via a genuine `queue_move`/`to_point` event (using the exact 3D center coordinates read from the hook) — verify via psql that `occupied_by_player_id` becomes 11 — criterion 7659.
- Attempt the garrison-fate choice (execute/release) — expected an execute/release button in the UI per criterion 7661/7662. **Actual: none exists.** Drive it via the same hook-eval workaround (`resolve_garrison_fate`) and check psql for unit deletions and `game_players.honor` deltas.
- Verify the occupied city keeps rendering "occupied" status and remains buildable by its original owner (criterion 7663) via the CityPanel.

## Result Path

Findings filed as issues via `create_issue`, final verdict submitted via `submit_qa_result` (task_id 2f3b72af-a232-4837-856b-07d94291851d). Screenshots at `.code_my_spec/qa/906/screenshots/`.

## Setup Notes

World 3 is intentionally a 2-region, 2-player world — there is no way to test criteria 7664 (occupying a non-last city leaves the owner free) or a genuine relief-heal race (7658) without a third city/player, which this session's sanctioned credentials didn't extend to. Both players in World 3 have exactly one city each, so every capture is a last-city capture by construction.

The story's core client-side gap (no Attack button, no garrison-fate choice button — see filed issues 56ee521a and ffa66192) required driving the real LiveView events directly via `vibium eval` + the Board hook's `pushEvent`, rather than clicking a UI element that doesn't exist. This is the same server-side code path a real button would invoke; only the click affordance is missing.
