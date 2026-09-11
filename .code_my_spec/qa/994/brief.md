# Qa Story Brief

## Tool

web

## Auth

Log in as two separate QA players (Open Borders is inherently two-party).
Use `#login_form_password` on `/users/log-in` (NOT the magic-link form):

- Player A: `qa-901-a@broken-oaths.test` / `qa-password-123!`
- Player B: `qa-901-b@broken-oaths.test` / `qa-password-123!`

Browser session isolation matters — either use two separate browser
contexts/tabs kept deliberately distinct, or log in/out serially and
re-verify the logged-in identity (page text / `known-players-panel`) before
each action, per plan.md's "MCP browser tools are unreliable" section.

## Seeds

    mix run priv/repo/qa_seeds_multiplayer.exs

This creates both QA players above, joins and founds them in "QA World
(Multiplayer)", and pre-seeds mutual discovery (`game_known_players`) so
both players already appear in each other's Known Players panel with no
in-session discovery step needed. It also stages a shared barbarian camp
target, which is irrelevant to this story — ignore it.

If the world's `/play/:id` URL isn't already known, read it from the
seed script's own printed output, or `GET /dev/qa/worlds/:id` against
candidate ids, or a `psql broken_oaths_dev` lookup of
`select id from worlds where name = 'QA World (Multiplayer)';`.

For criteria 2 and 4 (movement across the border), a unit needs to be
adjacent to a tile inside the partner's territory. The seed script does
not stage this by design (it stages a barbarian-assault scenario, not a
border-crossing one). Before those scenarios, read each player's city
tile and territory extent via `psql broken_oaths_dev` (cities table,
player_id, tile_id), then use the dev QA endpoint to place one of Player
A's units one tile outside Player B's territory, adjacent to a tile that
IS Player B's territory:

    curl -X POST http://localhost:4050/dev/qa/worlds/:id/pause
    curl -X PATCH http://localhost:4050/dev/qa/worlds/:id/units/:unit_id -d tile_id=<adjacent_to_border_tile>

Use `board_state.sh <tile_id>` (see below) to confirm real adjacency
before targeting a right-click move.

## What To Test

- **Criterion 3110 (propose/accept):** As Player A, open `/play/<world_id>`,
  open the Known Players panel (`[data-test='known-players-panel']`), find
  Player B's row (`[data-test='known-player-<player_b_user_id>']`), click
  the propose button (`[data-test='propose-open-borders-<player_b_user_id>']`).
  Expect it to flip to `[data-test='open-borders-pending-<player_b_user_id>']`
  ("Pending" text) on Player A's own view. Then, as Player B, expect the
  same row to show `[data-test='accept-open-borders-<player_a_user_id>']`;
  click it. Expect BOTH players' board state to now show
  `[data-test='open-borders-active-<counterparty_user_id>']` (a board
  overlay element, not the panel row itself — check page HTML/`browser_get_html`
  since it's an empty marker div) and the panel row to read
  `[data-test='revoke-open-borders-<counterparty_user_id>']`.

- **Criterion 3111 (peaceful movement):** With Open Borders active from
  the step above, and Player A's unit staged adjacent to a tile inside
  Player B's territory (see Seeds), right-click that tile via
  `board_click.sh <tile_id> right` while Player A is the active browser
  session. Expect the move to queue normally with NO
  `[data-test='declare-war-required']` banner appearing, and the unit's
  order to show it heading there (check `board_state.sh` for the unit's
  `order`). Step a turn (`POST .../dev/qa/worlds/:id/step`, once or twice
  depending on `world.economy_turns`/movement rules) and confirm the unit
  actually lands on that tile with no war having started
  (`[data-test='war-active-<player_b_user_id>']` / `[data-test='war-hostile-<player_b_user_id>']`
  should NOT appear).

- **Criterion 3112 (revoke):** As either player with an active agreement,
  click `[data-test='revoke-open-borders-<counterparty_user_id>']`. Expect
  the panel row to flip back to `[data-test='propose-open-borders-<counterparty_user_id>']`
  for both players, and the board overlay
  `[data-test='open-borders-active-<counterparty_user_id>']` to disappear
  from both sessions.

- **Criterion 3113 (blocked re-entry after revocation):** After revoking,
  reposition (or reuse) a unit adjacent to a tile in the former partner's
  territory and right-click it the same way as criterion 3111. Expect
  `[data-test='declare-war-required']` to appear ("Declare war before
  entering this territory.") instead of the move queuing peacefully, and
  the unit to NOT actually move into that tile on the next step. Confirm
  `[data-test='open-borders-active-<counterparty_user_id>']` is still
  absent (no accidental re-activation).

- **Note on `move_through_open_border`:** `play.ex` also defines a
  `"move_through_open_border"` LiveView event (comment: "a dedicated,
  directly-issuable order... not folded into `queue_move`'s own border
  gate") that only the BDD spex tests fire via `render_hook` — there is no
  button or DOM element wired to it anywhere in the app
  (`known_players_panel.ex`, `board_overlays.ex` checked). This is NOT a
  bug: `queue_move`'s real handler independently calls the same
  `Game.open_borders_active?/3` check (`play.ex:2213`, in
  `border_entry_status/3`), so the real player-facing move flow is
  correctly gated — test criteria 3111/3113 through the real `queue_move`
  path (right-click via `board_click.sh`) as described above, not by
  looking for a UI trigger for the synthetic event.

## Result Path

No result.md — findings go through `create_issue` as discovered; the run
ends with one `mcp__plugin_codemyspec_local__submit_qa_result` call
carrying `task_id`, `status`, `scenarios`, and `issue_ids`.

## Setup Notes

Board is canvas-only at `/play/:id` — use `board_click.sh <tile_id>
<left|right>` and `board_state.sh [tile_id]` from
`.code_my_spec/qa/scripts/` rather than DOM selectors for unit movement.
Always `board_state.sh` first to confirm a tile is in the fog-known set
and to compute real adjacency before targeting a click.

Pause the world (`POST .../dev/qa/worlds/:id/pause`) before any dev QA
unit repositioning, per plan.md's reload/catch-up warning, and resume
only once done if you want it live afterward (optional for this story —
leaving it paused doesn't affect anything else since this is a dedicated
two-player world).
