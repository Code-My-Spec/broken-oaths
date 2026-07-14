# Qa Story Brief

Story 875 — Queue Movement Orders.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Password form `#login_form_password`:
  - `input[name="user[email]"]`
  - `input[name="user[password]"]`
  - Submit button: `#login_form_password button[name='user[remember_me]']`
- Primary QA account: `qa@broken-oaths.test` / `qa-password-123!` —
  already a member of QA World (id 6). Its units as of this session:
  Lord (unit id 1) at tile 14741, Settler (unit id 2) at tile 14744,
  both `movement: 2/2`, no orders queued.
- Driven with the `mcp__plugin_codemyspec_vibium__*` browser MCP tools
  directly (not the `vibium` CLI). `browser_start`, `browser_navigate`,
  `browser_fill`, `browser_click`, `browser_evaluate`,
  `browser_mouse_click`, `browser_screenshot`.

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent, already run this session. Uses **QA World** (id 6, seed
424242, frequency 54). No story-specific seed needed — the QA
account's Lord and Settler already exist from prior sessions.

## What To Test

The board at `/play/:id` has **no tile DOM** — it's canvas-only (see
`lib/broken_oaths_web/live/game_live/play.ex` moduledoc, "board
doctrine"). Left-click on the canvas selects the unit on the clicked
tile; right-click queues the selected unit's move to the clicked
tile (`this.pushEvent("queue_move", ...)` in the colocated `.Board`
hook). Since there's no CSS selector per tile, real clicks are driven
by computing exact screen coordinates via the hook's own `project()`
method, reached through `window.liveSocket` (exposed in dev by
`assets/js/app.js`):

    window.liveSocket.owner(document.getElementById('board-viewport'), view => {
      const hook = view.viewHooks[Object.keys(view.viewHooks)[0]];
      // hook.tiles, hook.units, hook.project(x,y,z), hook.cx/cy give
      // everything needed to compute a real screen point for a tile id
      // present in hook.tiles (only fog-known tiles are click-able,
      // matching the fog-of-war doctrine).
    });

Then `browser_mouse_click({x, y, button: 0})` for left-click (select)
or `button: 2` for right-click (queue move) at the computed point.

Terrain/path facts below were computed with **read-only, pure**
`mix run` scripts against `BrokenOaths.Worlds.{Globe,Regions,Terrain,Generator}`
only — never `BrokenOaths.Game.*` (see Setup Notes: that starts a
competing `WorldServer` and is unsafe against the live server).

- **Clicking your lord shows the unit panel** (criterion 7424) — left
  click tile 14741 (Lord). Expect `[data-test='unit-panel']` to
  appear with `[data-test='unit-type']` = "Lord",
  `[data-test='unit-hp']` = "HP 20/20", `[data-test='unit-movement']`
  = "Movement 2/2".

- **You cannot path onto your own unit** (criterion 7430) — with Lord
  still selected, right-click tile 14744 (the Settler's own tile).
  Expect `[data-test='order-error']` to appear with the text "Another
  unit already holds that tile." (source:
  `order_error_message(:occupied)` in play.ex) and no path queued for
  the Lord.

- **Only the last order before the boundary counts** (criterion 7427)
  and **a path blocked mid-journey halts the unit without losing it**
  (criterion 7426), combined in one turn cycle:
  1. Left-click tile 14744 (Settler) to select it.
  2. Right-click tile 14784 — a decoy order (3-hex path
     `14744→14759→14772→14784`, confirmed uncontested/all-land by the
     BFS script). Expect a `game:path` push / `[data-test='unit-order']`
     showing "Moving to tile 14784".
  3. Right-click tile 14710 instead — the real order (3-hex path
     `14744→14728→14711→14710`). Expect `[data-test='unit-order']` to
     now show "Moving to tile 14710" — proving the decoy order was
     replaced, not queued alongside it.
  4. Left-click tile 14741 (Lord) to select it, then right-click tile
     14710 too — the *same* destination, reachable from the Lord in
     exactly 2 hexes (`14741→14726→14710`), so the Lord's full move
     completes in the next boundary while the Settler's needs two.
  5. Wait for the next turn boundary (watch `[data-test='turn-number']`
     increment). Expect: Lord now sits on 14710 (`hook.units` tile_id
     14710); Settler has advanced 2 of its 3 hexes, now on 14711, with
     its order still pending (1 hex remaining).
  6. Wait for the following turn boundary. Expect: the Settler's order
     resolution now finds 14710 occupied by the Lord and **halts the
     Settler at 14711** rather than displacing/losing it — confirm via
     `hook.units` (settler `tile_id` still 14711) and by left-clicking
     the Settler to see `[data-test='order-interrupted']` in the unit
     panel.

- **A settler walks a three-hex path over two turns** (criterion
  7425) — after the blocked-order scenario above, the Settler sits at
  14711 with an interrupted order. Re-plan a fresh, uncontested 3-hex
  path from wherever it currently sits (recompute neighbors with the
  same safe `Globe`/`Regions` scripts — do not reuse 14710, the Lord
  now occupies it) and queue it. Wait two turn boundaries. Expect the
  Settler to have advanced 2 hexes after the first boundary and the
  full 3 after the second, with `[data-test='unit-order']` clearing
  (no order / order consumed) once the destination is reached.

- **Ocean and mountains refuse a land unit** (criterion 7428) — not
  independently browser-tested this session. Both accounts' spawn
  regions on QA World (id 6) were checked by script
  (`Regions.tile_class/2` over the full region tile list) and are
  **100% `:land`** — zero mountain or coastal-water tiles anywhere in
  a ~226–262 tile region, with the nearest real coastline 13+ hops
  away (outside the currently-fogged/known tile set, and multiple
  real turns beyond reasonable QA-session time to walk to). Verified
  instead via source read: `do_queue_move/4` in
  `lib/broken_oaths/game/world_server.ex:332` rejects any `to_tile`
  where `Regions.tile_class(state.world, to_tile) != :land` with
  `{:error, :impassable}`, surfaced client-side as "That terrain
  can't be crossed." (`order_error_message(:impassable)`, play.ex).
  Corroborated by
  `test/spex/875_queue_movement_orders/criterion_7428_ocean_and_mountains_refuse_a_land_unit_spex.exs`.

- **Two units racing for the same hex resolve to one occupant**
  (criterion 7429) — not independently browser-tested this session.
  Requires two *different* players' units both within reach of a
  common hex in the same turn; the two seeded QA accounts' regions
  are on opposite, non-adjacent landmasses (not reachable from each
  other within any practical number of turns). The own-unit blocking
  scenario above (7426) exercises the same underlying "destination
  occupied at resolution time → halt" mechanism in `Turn`'s dynamic
  collision check, just with same-player units. Corroborated by
  source read of `Turn`'s resolution order and
  `test/spex/875_queue_movement_orders/criterion_7429_two_units_racing_for_the_same_hex_resolve_to_one_occupant_spex.exs`.

## Result Path

Findings are filed via `create_issue` as discovered; the run concludes
with one `submit_qa_result` call against task id
`d7c1c24f-25e6-4fac-bea3-ab17ada17b9b`. Screenshots go in
`.code_my_spec/qa/875/screenshots/`.

## Setup Notes

- **Do not call any `BrokenOaths.Game.*` function (or anything routed
  through `WorldServer.call/2`) from a separate `mix run`/`iex -S mix`
  process while the dev server is live.** `WorldServer` is addressed
  via a per-node `Registry`; a standalone script is a different BEAM
  node with its own empty registry, so it lazily starts a **second,
  independent** `WorldServer` for the same world id that runs its own
  catch-up/tick-persist logic against the shared Postgres row — this
  raced with the live server's own ticking earlier in this session and
  visibly slowed world 6's turn clock (see issue
  `07ee50d1-1cde-41dc-89bf-44ed63d5ddb5`). Pure reads through
  `BrokenOaths.Worlds.{Globe,Regions,Terrain,Generator,Weather}` are
  safe (no GenServer involved) and were used throughout this brief's
  prep to compute tile ids, neighbor lists, and BFS paths. Unit
  positions/state should instead be read live from the browser via
  `hook.units` (see above) — safe, and it's what the client actually
  sees.
- `window.liveSocket` is only exposed because `assets/js/app.js`
  intentionally sets `window.liveSocket = liveSocket` for dev console
  debugging — this is a dev-only affordance, not something to rely on
  in a deployed environment.
- Restarting the vibium browser session (`browser_stop`/`browser_start`)
  clears all cookies — re-login is required afterward.
