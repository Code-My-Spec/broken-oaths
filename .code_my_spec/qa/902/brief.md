# Qa Story Brief

Story 902 — Stone Age Technology Tree (`BrokenOathsWeb.GameLive.TechPanel`).

**Re-run context:** prior attempt 45f052c1 was PARTIAL — the tech tree
UI flow passed end-to-end, but a HIGH severity persistence bug (issue
957f4e55) meant `game_player_research` had zero rows for any World 1
player even after banking science / completing techs, and the
`board_click.sh` helper (issue e25fb72f) never actually fired
select/move due to a pointerId mismatch. Both are now marked resolved.
This session re-verifies the core UI flow at lighter depth and focuses
primarily on confirming persistence now genuinely works.

## Tool

web (vibium CLI via Bash, `dangerouslyDisableSandbox: true`) plus the
dev QA control surface (`curl` against `/dev/qa/worlds/1/*`) for
deterministic turn stepping, and `psql broken_oaths_dev` for read-only
ground truth on `game_player_research`, `game_improvements`, and
`game_cities`.

## Auth

Log in via the password form at `http://localhost:4050/users/log-in`:

    vibium go "http://localhost:4050/users/log-in"
    vibium fill "#login_form_password input[name='user[email]']" "qa@broken-oaths.test"
    vibium fill "#login_form_password input[name='user[password]']" "qa-password-123!"
    vibium click "#login_form_password button[type=submit]"

QA user `qa@broken-oaths.test` / `qa-password-123!` is already joined
to World 1 ("QA World") as `game_players.id = 1` with an existing
size-4 city (`game_cities.id = 1`, tile 14725).

## Seeds

No new seeds needed — `qa@broken-oaths.test` already has a founded,
grown city on World 1. Confirmed via psql pre-session: the WorldServer
boot backfill (fix for issue 957f4e55) has already created 8
`game_player_research` rows for World 1 (one per player), all with
empty `banked_science` (`{}`), null `current_research`, and empty
`completed_techs` (`{}`) — a clean starting point that also directly
proves the backfill-on-boot half of the fix.

World 1 must be PAUSED for the session
(`curl -X POST http://localhost:4050/dev/qa/worlds/1/pause`) so science
only accrues on explicit `POST /dev/qa/worlds/1/step` calls. Resume at
the end: `curl -X POST http://localhost:4050/dev/qa/worlds/1/resume`.

## What To Test

### Core flow re-verification (lighter pass — already proved live last time)

- Navigate to `http://localhost:4050/play/1`, confirm board loads.
- Click `[data-test='tech-tree-button']` — panel `[data-test='tech-panel']`
  opens showing all four techs with costs: Animal Husbandry 50,
  Pottery 50, Mining 75, Bronze Working 100. Criterion 7627.
- Verify `[data-test='science-per-turn']` reflects the city's income
  (2 * `game_cities.size`, cross-checked via psql). Criterion 7625.
- Select a tech, step turns via the dev QA control surface, confirm
  `[data-test='research-progress']` increases each step and never
  jumps straight to done before cost is reached. Criterion 7626/7631.
- Switch research mid-way and back — confirm per-tech banked progress
  is retained exactly. Criterion 7642.
- Bronze Working: confirm the "This will advance you to Bronze Age.
  Continue?" warning appears before committing, cancel works, confirm
  commits. Criterion 7630.
- Mining's 3-turn speedup: rely on the passing spex
  (`criterion_7628_mining_speeds_up_worker_mines_spex.exs`) again if no
  hills tile is reachable in the QA player's explored territory — note
  it as spex-covered rather than failing the story on it.

### Persistence re-verification (KEY new check — the reason for this re-run)

1. Confirm pre-session baseline via psql: `game_player_research` has 8
   rows for World 1 (the boot backfill), all empty/null — proves half
   of the fix (backfill on boot) before any play happens.
2. As the QA player on `/play/1`, select a research tech and step
   turns via `/dev/qa/worlds/1/step` to bank science. After EACH step,
   cross-check `game_player_research` via psql for
   `(world_id=1, player_id=1)`: confirm `banked_science` and
   `current_research` update in the DB row (not just the in-memory
   panel) — this is the upsert-on-every-write half of the fix.
3. Complete a tech (bank >= cost). Confirm via psql that
   `completed_techs` now contains the tech atom/string, persisted in
   the row.
4. Optional/strong evidence only if safe: note that WorldServer restart
   survival is already proven by the 3 new unit tests in
   `test/broken_oaths/game/world_server_test.exs` (describe "research
   persistence for a player with a missing PlayerResearch row") — do
   not attempt to force a live restart against the shared dev server
   mid-session (the QA plan's "System Issues" section flags dev-server
   restarts as destabilizing this project's own tooling); psql-verified
   row creation + updates during live play is sufficient corroboration
   alongside the test evidence.

## Result Path

Findings filed live via `create_issue` (issue_ids passed to
`submit_qa_result`) — no `result.md`. Screenshots saved to
`.code_my_spec/qa/902/screenshots/` (new persistence-focused screenshots
prefixed `10_` onward to avoid clobbering the prior session's evidence).
