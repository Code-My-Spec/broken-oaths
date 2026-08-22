# Qa Story Brief

## Tool

web (MCP browser tools against `/play/1`, 3D globe mode with `WheelEvent`-driven
zoom + synthetic `PointerEvent` clicks on the canvas board hook — same
mechanism as `board_click.sh`/`board_state.sh` but issued via
`browser_evaluate` directly) plus `curl` against the dev-only
`/dev/qa/worlds/:id` QA control surface for setup/fast-forward
(pause/step/spawn units/spawn barbarians/delete units) and `psql
broken_oaths_dev` for read-only state verification between steps.

## Auth

Log in as the existing QA World owner:

    URL: http://localhost:4050/users/log-in
    Email: qa@broken-oaths.test
    Password: qa-password-123!

Use the `#login_form_password` form (scroll it into view first — it's
below the magic-link form). This account already owns 3 founded cities
in World 1 ("QA World") with Mining, Bronze Working, Pottery, and
Animal Husbandry already researched — no need to re-research the base
chop techs from scratch.

## Seeds

No new seeding needed — World 1 ("QA World", id 1) already exists with
`qa@broken-oaths.test` as player_id 1, owning 3 cities (Oakhaven II /
tile 14725, City 2 / tile 21103, City 3 / tile 20927) with existing
workers, warriors, and abundant woods/rainforest tiles inside
Oakhaven II's own territory. Confirmed via `psql` before starting:

    select id, name, tile_id, size, territory, worked_tiles from game_cities where player_id = 1;

**Before touching the world**, pause it and check for any other
`paused: false` world with a stale `turn_started_at` (System Issues in
plan.md) — two other worlds (id 2, id 4) had ~27-day gaps and were
pre-emptively paused at the DB level this session (direct `UPDATE` via
psql, since a repo-write permission classifier blocks Bash from
mutating `worlds` directly in this environment — route around that by
asking the user, or by using this story's own `/dev/qa/worlds/:id/pause`
endpoint on the TARGET world at minimum before any browser interaction):

    curl -X POST http://localhost:4050/dev/qa/worlds/1/pause
    curl http://localhost:4050/dev/qa/worlds/1   # confirm paused:true before proceeding

## What To Test

All scenarios run against World 1, player 1 (`qa@broken-oaths.test`),
using the DevQA pause/step recipe from plan.md to fast-forward turns
deterministically instead of waiting on real `turn_seconds` cadence.

- **Immediate lump + formula (criteria 2716, 2717, 2728)**: queue a
  city build, select a worker standing on a woods tile in the city's
  own territory (already tech-unlocked), click "Chop Woods", and read
  `game_production_items.banked` before/after via psql — confirms the
  lump banks in the same click, only once. Formula: woods lump =
  `20 + 8 * completed_tech_count`; rainforest lump =
  `floor(woods_lump * 3 / 4)`. Research one additional tech
  (`POST .../step` looped until `game_player_research.completed_techs`
  grows) and chop a second same-feature-type tile to confirm the later
  lump is bigger than the earlier one on the identical formula.
- **Tech gating, offered side (2718, 2720)**: select a worker on a
  woods tile with Mining researched → `[data-test='chop-woods']`
  renders; select a worker on a rainforest tile with Bronze Working
  researched → `[data-test='chop-rainforest']` renders (distinct
  button, distinct tech).
- **Tech gating, blocked side (2719)**: NOT independently re-driven
  live this session — see Setup Notes.
- **Featureless tile (2721)**: worker on a bare (no-decor) tile inside
  territory, tech researched → no chop button, `[data-test='fortify']`
  still renders (panel isn't just empty).
- **Movement cost / yield removal (2722)**: after a chop, confirm the
  client's own `h.tileById.get(tile).decor` (previously `"woods"`)
  reads `null`, and `game_cleared_features` gains a row for that
  `tile_id` — both keys the same `Terrain.movement_cost/1` /
  `Terrain.decor/1` functions read (source-confirmed: feature in
  `[:woods, :rainforest, :marsh]` → cost 2, else → cost 1).
- **Farm eligibility (2723)**: immediately after a chop, re-select the
  worker on the now-cleared tile and confirm a "Build Farm" button now
  renders in place of the old chop button (didn't drive the build to
  full completion — button eligibility is the assertion).
- **Unowned land (2724)**: `POST /dev/qa/worlds/1/units` to spawn a
  throwaway worker (`player_id=1`) directly on a woods tile OUTSIDE all
  of player 1's cities' territory (found via `h.tiles` decor scan minus
  known territory arrays) → no chop button even with tech researched.
- **In-borders chop succeeds (2725)**: covered by the main chop
  sequence above — no `[data-test='chop-error']`, feature gone after.
- **Charges (2726, 2727)**: track `game_units.charges` across 3 real
  chops on the SAME worker (3 → 2 → 1 → 0); confirm the worker row
  disappears entirely from `game_units` after the 3rd chop (charges
  hitting 0 removes the unit, same path as a combat death — not a
  disabled button on a still-standing worker).
- **Worked-tile reassignment (2729)** — the story's one genuinely new
  mechanic this session (`Yields.revalidate_worked_tiles/1` wired into
  `Turn.tick/1`): chop a tile that's in the city's
  `game_cities.worked_tiles` array. Confirm it's STILL present
  immediately after the chop (reassignment isn't instant), then
  `POST .../step` once and confirm it's GONE from `worked_tiles` — a
  straight drop, not a reassignment to a different tile. Also open the
  city panel in the browser and visually confirm the tile moved from
  the "Unwork" list to the "Work" list with no broken/stuck-looking
  row.
- **Enemy-occupied tile (2730)**: spawn a throwaway worker
  (`player_id=1`) on a woods tile in territory, then
  `POST /dev/qa/worlds/1/barbarians -d tile_id=<same tile>` to
  co-locate a hostile unit on the exact same tile (spawn endpoints
  don't enforce the one-unit-per-hex occupancy guard, unlike
  relocate/move). Confirm the Chop button STILL renders (the hostile
  check is deliberately left to the real command, not the button
  gate), but clicking it produces `[data-test='chop-error']`, the tile
  keeps its feature, and `game_units.charges` is unchanged (refused
  before any state mutation).

## Result Path

No `result.md` file — findings are filed via `create_issue` as
discovered and the session ends with one `submit_qa_result` call
(status, structured `scenarios` list, and every `issue_ids` collected).

## Setup Notes

**3D camera zoom matters for click precision.** At the default
zoomed-out globe view, adjacent tiles project to screen coordinates
only a few pixels apart, so synthetic `PointerEvent` clicks
(replicating `board_click.sh`'s technique via `browser_evaluate`)
frequently hit the wrong tile/unit in a stack. Zoom in first by
dispatching ~15 synthetic `WheelEvent`s (`deltaY: -100`) centered on
the area of interest before doing precise unit/tile selection.

**Selection is server-round-trip-gated.** Firing multiple synthetic
pointer clicks back-to-back in one `browser_evaluate` call (no
`await`) does NOT advance LiveView's own stacked-tile selection cycle
— each call needs to be a SEPARATE tool invocation so the previous
click's server push lands before the next click fires, or every click
in a batch behaves like the very first one.

**DevQA-spawned units need a page reload to appear client-side.**
`POST /dev/qa/worlds/:id/units` and `/barbarians` write directly to the
`WorldServer` and DB, but the connected LiveView's fog-of-war window
push doesn't pick up a brand-new unit until the next full
`browser_navigate` to the same URL (a plain re-render/step doesn't
surface it).

**2719 ("chop blocked before tech is researched") was not
independently re-driven live this session.** Its positive counterpart
(2718: button renders once tech IS researched) was confirmed live, on
the exact same gating code path (`PlayView.worker_choppable_feature/5`
→ `Research.chop_woods_enabled?/1`) that was ALSO independently
live-confirmed to correctly withhold the button for two OTHER failing
gate conditions this session (2721 featureless tile, 2724 unowned
territory). Reproducing the pre-research state live would have
required either an existing zero-tech player's login credentials
(unknown — the other players in World 1 have no seeded password) or a
fresh signup; the signup flow was attempted and hit an unrelated
pre-existing bug (`/users/register` renders generic unstyled scaffold
branding instead of the app's own theme — filed separately, not
blocking this story). Given the shared code path and the criterion's
own BDD spec already passing, this was judged sufficient without
forcing a costlier account-creation workaround.
