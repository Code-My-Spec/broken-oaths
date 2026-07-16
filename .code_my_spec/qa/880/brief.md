# Qa Story Brief

Story 880 — City Growth.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Password form `#login_form_password`:
  - `input[name="user[email]"]`
  - `input[name="user[password]"]`
  - Submit button: `#login_form_password button[name='user[remember_me]']`
- Existing QA user: `qa@broken-oaths.test` / `qa-password-123!` — player 1
  on world 6 ("QA World", Oakhaven, city 1, size 4) and player 10 on
  world 1 ("Jade Wilds", city 4 "City 1", size 3). Both cities are past
  size 1 already (see Seeds section) — useful for the size-4 cap
  criterion (7477) and worked-tile UI checks (7476), but NOT for a
  clean size-1→2 live transition (7475/7474).
- New throwaway account for the clean size-1→2 transition: register at
  `http://localhost:4050/users/register` with email
  `qa880-fresh@broken-oaths.test` (magic-link flow, no password needed
  to register — read the confirmation link from
  `http://localhost:4050/dev/mailbox`, Swoosh local adapter). Join
  **world 6** ("QA World", id 6) from `/play` to get a fresh lord +
  settler.
- Driven with `mcp__vibium__browser_*` tools (or the `vibium` CLI with
  sandbox disabled if MCP tools aren't present this session).
- The board (`/play/:id`) is canvas-only — no tile DOM for
  selection/founding. Founding a city and dispatching commands are
  driven via `window.liveSocket`'s hook-eval workaround (documented in
  `.code_my_spec/qa/878/brief.md` and reused in 879):

      window.liveSocket.owner(document.getElementById('board-viewport'), view => {
        const hook = view.viewHooks[Object.keys(view.viewHooks)[0]];
        hook.pushEvent('found_city', {unit_id: <settler_id>});
      });

  This dispatches through the exact same `Play.handle_event/3` code
  path as a real click. Once a city is selected, `[data-test='city-panel']`
  is a real DOM node — the buttons inside it
  (`[data-test='production-option-*']`, `[data-test='city-worked-tile-<id>']`
  Work/Unwork buttons, `[data-test='city-name-form']`) can be
  clicked/filled directly with real DOM interaction to exercise actual
  wiring.

  **Known bug context — re-verify empirically, don't assume:**
  `found_city` was found broken via a REAL button click in two prior
  sessions this batch (878, 879), even though source
  (`lib/broken_oaths_web/live/game_live/play.ex` `found_city` handler,
  ~line 199-206) already calls `parse_id/1` on `unit_id` — same as
  `queue_production`/`cancel_production_item`, both of which 879
  confirmed fixed via real clicks. Filed as
  `ee6f7ccb-352d-4948-81aa-c3669f9cc2d9` (high, story 879, status
  incoming) as a DISTINCT issue from the original `a1c8741d` (which
  only ever named `queue_production`/`cancel_production_item`, not
  `found_city`). For the new throwaway account's settler, try the REAL
  `[data-test='found-city']` button first (in `GameLive.UnitPanel`,
  after `select_unit`) and observe the actual result directly — record
  in the scenario observation whether it succeeds or still fails with
  "You don't control that city." If it still fails, fall back to the
  `liveSocket` hook technique to keep the session moving and note the
  bug is still present; do not file a duplicate, just corroborate
  `ee6f7ccb` (or note if it now looks fixed).

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent — already current, do not re-run unless state looks wrong.
DB state re-verified via psql immediately before writing this brief
(`psql broken_oaths_dev`, sandbox disabled):

- **World 6** ("QA World", id 6, frequency 54, turn ~2565 at brief
  time, ~104 spawnable regions — plenty of room for a new throwaway
  join): QA user `qa@broken-oaths.test` is player 1, city 1
  "Oakhaven" at tile 21635, **size 4**, food 470 (climbing — was 440 a
  session ago, now 470, still size 4: strong live evidence the cap
  holds and food banking continues uncapped), territory 10 tiles,
  worked_tiles `{21634,21607,21578,21606}`. Do not touch this city's
  worked-tile assignments — it's the load-bearing evidence for 7477 as
  a "long-observed, still capped" case; only read it, don't mutate it.
- **World 1** ("Jade Wilds", id 1): QA user is player 10, city 4 "City
  1" at tile 6526, **size 3**, food 14, territory 9 tiles, worked_tiles
  `{6483,6484,6527}` (3 worked tiles for size 3 — corroborates 7476's
  "N worked tiles for size N" rule as a secondary read-only check,
  distinct from the live size-2 city built fresh this session).
- **World 10** ("QA World (Fill Test)", id 10): two other throwaway
  cities exist here (`throwaway1@example.test` city 2, size 4, food
  258; `qa873-fillb@broken-oaths.test` city 3, size 4, food 37) — not
  needed for this story, leave untouched.
- **No existing size-1 city anywhere in the DB** — every city from
  prior QA sessions has already grown past size 1 because turns tick
  continuously (60s wall-clock) regardless of who's watching. **A
  brand-new city is required for 7474/7475's live size-1→2
  transition.** Register `qa880-fresh@broken-oaths.test`, join world 6,
  found a city immediately after confirming the settler's tile is land.
- Turn boundary is 60s wall-clock. Grab the current turn via
  `psql broken_oaths_dev -c "SELECT id, turn, turn_started_at FROM worlds WHERE id = 6;"`
  and poll `worlds.turn` (or `game_cities.food`/`.size`/`.territory`
  directly) across boundaries rather than eyeballing the UI in real
  time — track state via psql at ~30-60s intervals, not by watching
  continuously.
- **Never call `BrokenOaths.Game.*` from a second `iex`/`mix run`
  process** while the dev server runs — competing `WorldServer` risk.
  `BrokenOaths.Worlds.*` / `Globe` / `Terrain` / `Regions` calls, AND
  `BrokenOaths.Game.Yields` / `BrokenOaths.Game.Production` (both pure,
  no `Repo`/GenServer — confirmed by reading source and moduledocs)
  ARE iex-safe for verifying the yield-stacking formula and food
  thresholds without touching the live world's state. psql and vibium
  both need the sandbox disabled.

## What To Test

- **7474 (growth claims exactly one new tile) + 7475 (20 food ⇒
  size 2)** — new throwaway account, world 6:
  1. Register `qa880-fresh@broken-oaths.test`, confirm via
     `/dev/mailbox`, log in.
  2. Go to `/play`, join world 6, go to `/play/6`.
  3. Identify the new settler's unit id and tile via the sidebar/unit
     panel (or `select_unit` push). Confirm the settler's tile is land
     (sidebar terrain readout, or a pure `Regions.terrain/2` probe).
  4. Try the REAL `[data-test='found-city']` button first (see Auth
     section's known-bug note); fall back to the `liveSocket` hook if
     it fails.
  5. Record the new city's id, tile_id, and starting `territory`
     (7 tiles) and `food` (0) via psql immediately after founding —
     this is `city_before` for 7474.
  6. Poll `game_cities` (this city's row) via psql every ~30-60s.
     Expect roughly 4-5 food/turn at size 1 (base + 1 worked tile).
     Confirm `food` climbs turn-over-turn.
  7. When `size` flips from 1 to 2 (should be within ~10 min, at
     `food >= 20`), immediately snapshot via psql: new `territory`
     (should be 8 tiles = +1 vs `city_before`), new `worked_tiles`
     (should gain a second entry per 7476), and `food` (should be the
     overflow past 20, not a jump back to 0 — confirms `settle_growth`
     carries remainder, `food - threshold`).
  8. Compute `MapSet.difference` of before/after territory by hand
     (or eyeball the two tile-id lists) — confirm exactly one new tile,
     and that it's adjacent to a `city_before.territory` tile (visually
     reasonable, or corroborate via a pure `Regions.adjacent_tiles/2`
     iex probe).
  9. Screenshot the city panel (`[data-test='city-panel']`) showing
     `[data-test='city-size']` = "2" and `[data-test='city-food']`
     showing the post-growth overflow value.
  10. This is the load-bearing LIVE evidence for both 7474 and 7475 —
      do not skip; time-box the wait to ~10-12 minutes of psql polling
      at wide intervals.

- **7476 (each citizen works one tile beyond the free center)** — same
  new city from above, right after the size-2 transition:
  1. Confirm via psql: `worked_tiles` has exactly 2 entries (size 2 ⇒
     2 worked tiles beyond the always-free center at `tile_id`), and
     the city's own `tile_id` is NOT in `worked_tiles` (it's the free
     center, shown separately in the panel).
  2. In the UI: select the city (`select_city` push if canvas-only, or
     click if a real affordance exists), confirm
     `[data-test='city-worked-tile-<city.tile_id>']` renders labeled
     "Free" for the center, and `[data-test='city-worked-tile-<id>']`
     renders for each of the 2 worked tiles with an "Unwork" button.
  3. Confirm at least one assignable (unworked, owned, workable)
     territory tile renders with a "Work" button
     (`assign_worked_tile` with `to_tile_id`) if the city's territory
     has spare workable tiles beyond the 2 worked + center.
  4. Exercise reassignment: click "Unwork" on one worked tile, confirm
     via psql it drops from `worked_tiles`; click "Work" on a different
     assignable tile, confirm via psql it's added. Screenshot before
     and after.
  5. Secondary read-only corroboration: confirm world-1 city 4 (size 3)
     has exactly 3 `worked_tiles` and world-6 Oakhaven (size 4) has
     exactly 4 `worked_tiles` — consistent with "N pop ⇒ N worked
     tiles" across multiple observed sizes, without mutating those
     cities.

- **7477 (size-4 city stops growing until the age turns)** — world 6,
  Oakhaven (city 1, already size 4, food climbing past any plausible
  threshold):
  1. Snapshot `food` via psql now, wait ~2-3 turn boundaries (~2-3
     min), snapshot `food` again. Confirm `size` is unchanged (still
     4) and `food` has increased (banking continues, not frozen) —
     this directly answers "does food keep climbing with no growth."
  2. Cross-check against source: `BrokenOaths.Game.Yields.threshold/1`
     returns `nil` for any size ≥ 4 (i.e. `threshold(_capped)`), so
     `grow/3`'s `case threshold(city.size) do nil -> city` short-
     circuits — no claim, no size bump, no food deduction — while
     `Turn.tick/1`'s `accrue_food/1` phase runs unconditionally before
     the growth phase, independent of cap state. This is a pure,
     iex-safe read (`BrokenOaths.Game.Yields.threshold(4)` — no
     GenServer/Repo call) — confirm it returns `nil` and
     `BrokenOaths.Game.Yields.capped?(4)` returns `true`.
  3. Confirm no crash/error and no unit/city loss: `game_units` still
     has Oakhaven's garrisoned units, `game_cities` row for city 1
     still exists and is well-formed.
  4. Screenshot the city panel showing `[data-test='city-size']` = "4"
     and the food readout label ("Capped" per `food_label(nil)` in
     `city_panel.ex`, since `food_threshold` is `nil` at cap — confirm
     this exact UI text, it's a concrete assertion, not just "some
     number").

- **7490 (yields stack: forested grassland hills feed and build at
  once)** — time-box to ~10 minutes; prefer live verification, fall
  back to code-verification if no reachable stacked tile is found in
  time:
  1. Read `BrokenOaths.Game.Yields` (`tile_yield/1`, `base_yield/1`,
     `relief_bonus/1`, `feature_food_bonus/1`,
     `feature_production_bonus/1`) — already reviewed while writing
     this brief. The stacking formula is `yield = base + relief +
     feature`, additive: grassland base = `{food: 2, production: 0}`,
     `:hills` relief = `+1 production`, `:woods` feature =
     `+1 production` (not food — only `:rainforest`/`:marsh` add
     food). A tile with base `:grassland`, relief `:hills`, feature
     `:woods` therefore yields exactly `{food: 2, production: 2}` —
     this is the codified expectation to verify against, not a guess.
  2. Hunt for a live grassland+hills+woods tile reachable from an
     existing or new city's territory (world 6 or world 1) via a pure
     iex probe over `BrokenOaths.Worlds.Regions.terrain/2` across a
     land region near an existing settler/city. Per the BDD spec
     (`criterion_7490_..._spex.exs`), this exact combination does NOT
     occur anywhere on the default fixture seed (424242, world 6's
     seed) — the spec had to scan a bespoke seed (33) to find one. Do
     not expect to find it on world 6 or world 1 within the time-box;
     confirm this negative (or a positive, if you get lucky) via a
     quick iex scan, then move to code-verification.
  3. If a live stacked tile isn't reachable in time: check whether ANY
     worked tile among the existing cities (Oakhaven's
     `{21634,21607,21578,21606}`, world-1 city 4's `{6483,6484,6527}`,
     etc.) has 2+ stacked modifiers of any kind (e.g. hills+woods
     without grassland, or a food-stacking rainforest+hills tile) —
     even a partial stack corroborates additive composition live. Use
     `BrokenOaths.Worlds.Regions.terrain/2` (pure, iex-safe) to read
     each worked tile's `base`/`relief`/`feature` and manually sum
     against the formula above; compare against the city's actual
     per-turn food/production delta if isolable (unassign the tile,
     wait one turn, reassign, wait one turn, diff the city's
     `food`/queue `banked` deltas — same technique the BDD spec uses).
  4. Report explicitly whether 7490 was exercised live (full 3-tile
     stack, partial stack, or neither) vs. code-verified-only, and cite
     the exact formula/numbers checked either way — do not skip this
     criterion silently.

## Result Path

No `result.md` file — findings are filed via `create_issue` as
discovered and the session concludes with one `submit_qa_result` call
against task id `783ff3fd-d117-40db-ba23-07c4edfc410c`. Screenshots go
in `.code_my_spec/qa/880/screenshots/`, raw psql/iex evidence
transcripts in `.code_my_spec/qa/880/responses/`.

## Setup Notes

- Dev server is already running at `http://localhost:4050` — do not
  restart it, do not run `mix phx.server`/`mix compile`/`mix format`/
  `mix test`/`mix spex`.
- `psql broken_oaths_dev` and `vibium` both require the sandbox
  disabled (`dangerouslyDisableSandbox: true`).
- Time-box aggressively: this is one of several sequential QA sessions
  in a ~2.5-hour batch. The 7474/7475 size-1→2 wait (~10-12 min) is
  the single biggest time sink — start it first, interleave 7476/7477/
  7490 work while polling.
- Do not file a duplicate issue for the known `found_city` real-click
  bug — reference `ee6f7ccb-352d-4948-81aa-c3669f9cc2d9` (and its
  distinct predecessor `a1c8741d-a889-409c-aad6-d17166e7e7b0`) instead;
  corroborate current status in the scenario observation rather than
  re-filing.
- Leave the new throwaway city's exact id/world/size/tile in the final
  report — stories 881-883 may want to reuse it as a fresh, low-size
  city (rare resource in this batch, since everything else has already
  grown past size 1-2).
