# Qa Story Brief

Story 878 — Settler Founds City.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Password form `#login_form_password`:
  - `input[name="user[email]"]`
  - `input[name="user[password]"]`
  - Submit button: `#login_form_password button[name='user[remember_me]']`
- Primary account (world 6, "QA World"): `qa@broken-oaths.test` /
  `qa-password-123!`.
- World 10 ("QA World (Fill Test)") accounts have no password —
  authenticate via magic link: submit `#login_form_magic` with
  `input[name="user[email]"]`, then read the link from
  `http://localhost:4050/dev/mailbox` (Swoosh local adapter):
  - `throwaway1@example.test` (player 3, lord unit 5 @ tile 159,
    settler unit 6 @ tile 42)
  - `qa873-fillb@broken-oaths.test` (player 11, lord unit 21 @ tile
    581, settler unit 22 @ tile 575)
- Driven with the `vibium` CLI directly (bash tool, sandbox disabled)
  — no MCP browser tools are present in this session. Key commands:
  `vibium go <url>`, `vibium fill <selector> <text>`, `vibium click
  <selector>`, `vibium eval <js>` / `vibium eval --stdin`, `vibium
  screenshot` (always writes `~/Pictures/Vibium/screenshot.png` — copy
  aside per scenario, the path argument is broken). If vibium wedges:
  `pkill -f chrome-for-testing; pkill -x vibium; rm -f
  ~/Library/Caches/vibium/vibium.sock`, then `vibium go` again (lands
  on `about:blank`, always re-navigate).
- The board (`/play/:id`) is canvas-only — no tile DOM. Unit selection
  and city selection are normally driven by canvas clicks computed via
  `hook.project()` (see `.code_my_spec/qa/875/brief.md`). Founding and
  renaming, however, are exercised more reliably and just as validly
  (still over the live LiveView socket, not `render_hook` in-process)
  via `window.liveSocket`, which `assets/js/app.js` exposes in dev:

      window.liveSocket.owner(document.getElementById('board-viewport'), view => {
        const hook = view.viewHooks[Object.keys(view.viewHooks)[0]];
        hook.pushEvent('found_city', {unit_id: <settler_id>});
      });

  `found_city`/`select_city`/`queue_move` (with a `to_tile` key
  instead of `to_point`) all dispatch to `Play.handle_event/3` the same
  way whether pushed by a real click or this hook-level `pushEvent` —
  it is the same LiveView process, same socket, same code path. Once a
  unit/city is selected this way, the resulting `[data-test='unit-panel']`
  / `[data-test='city-panel']` (Found City button, city-name-form) are
  real DOM elements — click/fill those directly with `vibium
  click`/`vibium fill` to exercise the actual DOM wiring, not just the
  server-side handler.

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent — already current. No story-specific seeds needed; DB state
was re-verified via psql immediately before writing this brief:

- World 6 (id 6, seed 424242, freq 54): QA user is player 1, settler
  unit 2 @ tile **21635**, confirmed via a pure `mix run` probe script
  (`BrokenOaths.Worlds.Regions.terrain/2`) to be
  `%Terrain{base: :grassland, relief: :flat, feature: :woods}`,
  `tile_class: :land`, with **6** adjacent tiles (not a pentagon) —
  ideal for founding in place with a clean 7-tile territory assertion.
  No city exists for any of world 6's 4 players yet.
- World 10 (id 10, seed 111222, freq 8, 642 tiles): player 3
  (throwaway1) settler @ tile 42 (grassland, land); player 11
  (qa873-fillb) settler @ tile 575 (snow, land). Land-distance between
  them is **19 hexes** (BFS-confirmed) — too far to close by walking
  one settler alone within a reasonable time-box, so both settlers are
  queued toward each other's tile simultaneously (2 hexes/turn each,
  ~4 hexes/turn combined closing speed, ~5 turns to converge) while
  other scenarios run in parallel. `Production.founding_territory/2`
  needs no DB access to compute expected territory — it's `tile_id`
  plus `Regions.adjacent_tiles/2`, read live via psql once the actual
  founding tiles are known.
- No `BrokenOaths.Game.*` calls from a separate `mix run`/`iex`
  process — competing `WorldServer` risk. All probe scripts above used
  only `BrokenOaths.Worlds.{Regions,Terrain,Globe}`, which are pure.

## What To Test

- **7461 (founds on the grassland it stands on) + 7463 (settler
  traded for a working size-1 city) + 7464 (exactly seven tiles) +
  7466 (default name, renameable)** — all exercised in one pass on
  world 6:
  1. Log in as `qa@broken-oaths.test`, go to `/play/6`.
  2. Via the `window.liveSocket` hook technique, push `found_city`
     with `unit_id: 2` (the settler on tile 21635, grassland).
  3. Confirm via psql (`game_units`, `game_cities` for world 6, player
     1) that unit 2 is gone and a new `game_cities` row exists at
     `tile_id = 21635`, `size = 1`, with a non-empty default `name`.
  4. Confirm `territory` is exactly 7 tile ids: `{21635, 21661, 21662,
     21636, 21608, 21607, 21634}` (center + the 6 neighbors from the
     probe script).
  5. In the browser: push `select_city` with the new city's id via the
     same hook technique, screenshot the resulting `[data-test='city-panel']`
     showing a non-blank `[data-test='city-name']`.
  6. Fill and submit the real DOM `[data-test='city-name-form']` with
     a new name (e.g. "Oakhaven"), confirm `[data-test='city-name']`
     updates in the DOM and persists in psql after a fresh
     `/play/6` navigation + re-`select_city` push.
  7. Click a real `[data-test='production-option-warrior']` button (or
     equivalent) in the city panel to confirm production can be queued
     immediately — `[data-test='city-production-current']` should
     appear with no turn boundary required.

- **7462 (founding too close to an existing city is refused with a
  reason) + 7465 (a minimum-spacing neighbor never steals claimed
  tiles)** — on world 10, using throwaway1 and qa873-fillb:
  1. Log in as both (two sequential vibium sessions or a second
     profile — cookies are per-browser-session, so log out/in between
     acting as each user is fine since this scenario doesn't need both
     connected at once).
  2. Queue both settlers toward each other (`queue_move` with
     `to_tile: 575` for unit 6, `to_tile: 42` for unit 22) via the
     hook technique, then wait ~5 turns (turn boundary is 60s
     wall-clock; poll psql `game_units.tile_id` every minute or so)
     until they're close.
  3. Found a city with whichever settler is more conveniently
     positioned once they've converged (confirm via psql the tile is
     land). Compute (fresh probe script) the ring-3 and ring-4
     land-distance sets from that tile.
  4. Move the second settler to a ring-3 tile (still land, per the BFS
     sets), attempt `found_city` — expect `:ok` to NOT happen: no new
     `game_cities` row for that player, and the browser shows
     `[data-test='city-error']` with a "too close" message
     (`city_error_message(:too_close)` in `play.ex`, "Too close to an
     existing city."). Screenshot the error. Confirm via psql the
     settler unit still exists (not consumed).
  5. Move the same settler on to a ring-4 tile, attempt `found_city`
     again — expect success: new `game_cities` row, settler gone.
  6. Via psql, confirm the two cities' `territory` arrays have zero
     overlap (`SELECT territory FROM game_cities WHERE world_id = 10`,
     diff the two arrays).
  7. If time allows, exercise the deeper "shared growth candidate"
     intent behind 7465 (per the spex's own moduledoc: minimum spacing
     alone doesn't prevent territory overlap at growth time — a
     size-1→2 growth can reach a tile that's also in the neighbor's
     candidate set) by growing the first city once (queue a
     `warrior`/production item is NOT growth — growth is size, driven
     by food/turns; this needs real wall-clock turns to reach size 2)
     and confirming via psql that its territory still excludes
     whatever the second city already claims. Time-box this sub-step;
     if it doesn't fit, note it as not independently verified and rely
     on the spex (`criterion_7465...spex.exs`) as the corroborating
     unit-level proof, same pattern used in the 875 QA session for
     scenarios that don't fit a live wall-clock budget.

## Result Path

Findings are filed via `create_issue` as discovered (not written to a
result file); the QA run concludes with one `submit_qa_result` call
against task id `64ab2185-fca3-4f08-8479-5bf9573a051d`. Screenshots go
in `.code_my_spec/qa/878/screenshots/`, raw psql/API evidence in
`.code_my_spec/qa/878/responses/`.

## Setup Notes

- Dev server is already running at `http://localhost:4050` — do not
  restart it, do not run `mix phx.server`/`mix compile`/`mix format`.
- `psql broken_oaths_dev` and `vibium` both require the sandbox
  disabled (`dangerouslyDisableSandbox: true`) per the QA plan.
- Turn boundary is 60s wall-clock — the spacing scenario's convergence
  walk is the long pole; interleave the world-6 founding scenario
  (7461/7463/7464/7466, no movement needed) while waiting on it.
- World 6 has two OTHER players that must not be touched:
  `johns10@gmail.com` (the real operator's own account — never
  interact with its units/city) and `qa877-throwaway2@example.test`
  (a different concurrent QA story's fixture). Only player 1
  (`qa@broken-oaths.test`) is in scope on world 6.
- The barbarian-camp-on-first-city consequence mentioned in the story
  source is explicitly out of scope for this story (belongs to a
  future barbarian story) — do not test or block on it.
