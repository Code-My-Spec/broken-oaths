# QA Brief: Story 999 - Limit Military Production in Occupied Cities

## Tool

web (vibium CLI)

## Auth

Log in as two accounts on the same paused multiplayer world:

- Player A: qa-901-a@broken-oaths.test / qa-password-123! (player_id 11, owns city 8)
- Player B: qa-901-b@broken-oaths.test / qa-password-123! (player_id 12, owns city 9)

    vibium go "http://localhost:4050/users/log-in"
    vibium find "#login_form_password"
    # fill email/password, submit

Use a fresh vibium session per account (log out between, or use two profiles) since only one page pointer is reliable at a time per the plan's System Issues section.

## Seeds

World 3 already has the scenario staged from a prior session (qa_seeds_multiplayer.exs, then hand-occupied for story 998's QA): city 8 (player 11's, occupied_by_player_id=12) and city 9 (player 12's, occupied_by_player_id=11), world paused. Confirm before testing:

    curl http://localhost:4050/dev/qa/worlds/3

Expect `"paused": true`. If either city's occupied_by_player_id has been cleared since, restore via:

    UPDATE game_cities SET occupied_by_player_id = 12 WHERE id = 8;
    UPDATE game_cities SET occupied_by_player_id = 11 WHERE id = 9;

(via `psql broken_oaths_dev`, not a second BEAM node)

## What To Test

- **Criterion 3136 (ownership preserved):** As player A, navigate to `/play/3`, select city 8 (own, occupied). Confirm the city panel still shows player A as owner and displays an "occupied" status indicator. Cross-check `player_id` is unchanged in the DB.
- **Criterion 3137 (cannot raise military units):** In city 8's production/build list (city_panel.ex), confirm military items (warrior, bronze_spearman, archer, galley, scout — see `Occupation.military_item?/1`) are NOT offered as buildable options, while non-military items (e.g. granary, wealth) still are. Attempt to queue a military item directly if the UI exposes any path to do so (e.g. via `Production.can_queue?/3` guard) and confirm it's rejected.
- **Criterion 3138 (reclaiming restores production):** Clear the occupation (`UPDATE game_cities SET occupied_by_player_id = NULL WHERE id = 8;`), reload city 8's panel, and confirm military items reappear in the build list and can be queued.
- Repeat the ownership/military-block check symmetrically for city 9 (player B, occupied by A) as a second data point.

## Result Path

DB-backed QA attempt via `submit_qa_result` (task_id 58c1e056-a44e-4a22-acf5-02db6e8c4411) — no result.md file.

## Setup Notes

`Occupation.validate_production/2` is called from `production.ex:612` (queueing) and `:662` (produce_wealth), and `city_panel.ex:146` filters the offered build list via `Occupation.available_items/2` — confirmed wired in via source read, not dead code. World 3 is paused so no wall-clock catch-up will disturb the scenario mid-session.
