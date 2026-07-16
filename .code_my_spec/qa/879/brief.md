# Qa Story Brief

Story 879 — City Production Queue.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Password form `#login_form_password`:
  - `input[name="user[email]"]`
  - `input[name="user[password]"]`
  - Submit button: `#login_form_password button[name='user[remember_me]']`
- QA user: `qa@broken-oaths.test` / `qa-password-123!` — this account is
  player 1 on world 6 ("QA World") and player 10 on world 1 ("Jade
  Wilds"). Both are in scope for this story; no other accounts needed.
- Driven with `mcp__vibium__browser_*` tools (or the `vibium` CLI with
  sandbox disabled if MCP tools aren't present this session).
- The board (`/play/:id`) is canvas-only — no tile DOM. Unit/city
  selection is normally driven by canvas clicks. Founding, production,
  and cancellation are exercised more reliably via `window.liveSocket`,
  which `assets/js/app.js` exposes in dev — same technique documented
  in `.code_my_spec/qa/878/brief.md`:

      window.liveSocket.owner(document.getElementById('board-viewport'), view => {
        const hook = view.viewHooks[Object.keys(view.viewHooks)[0]];
        hook.pushEvent('found_city', {unit_id: <settler_id>});
      });

  This dispatches through the exact same `Play.handle_event/3` code
  path as a real click — same LiveView process, same socket. Once a
  city is selected this way, `[data-test='city-panel']` is a real DOM
  node; buttons inside it (`[data-test='production-option-warrior']`,
  the queue's `Cancel` buttons, `[data-test='city-name-form']`) can be
  clicked/filled directly with `vibium click`/`vibium fill` to exercise
  the actual DOM wiring.

  **IMPORTANT — re-verify the known bug empirically before assuming it
  still applies.** Issue `a1c8741d-a889-409c-aad6-d17166e7e7b0` (filed
  during story 878 QA) reported that `found_city`, `queue_production`,
  and `cancel_production_item` in
  `lib/broken_oaths_web/live/game_live/play.ex` passed string
  `phx-value-*` params straight into integer-keyed `WorldServer` state,
  causing every real-button click to fail with "You don't control that
  city." **A source read done while writing this brief shows all three
  handlers now call `parse_id/1` on their id params** (lines ~202, 211,
  220) — this looks like it may already be fixed since 878's QA pass,
  even though the issue is still `status: incoming`. Do not assume
  either way — for the FIRST scenario only, click the real
  `[data-test='production-option-warrior']` button (not the hook) and
  observe directly: if it fails with "You don't control that city",
  the bug is confirmed still live, corroborate `a1c8741d` and drive the
  rest of the session via the hook workaround as originally planned.
  If it succeeds, note this as a positive finding (bug appears fixed)
  and feel free to use real DOM clicks for the remainder of the
  session — but keep the hook technique in your back pocket for
  city/unit *selection* either way (canvas has no clickable DOM).

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent — already current, do not re-run unless state looks wrong.
DB state re-verified via psql immediately before writing this brief:

- `game_production_items` is empty everywhere — clean slate.
- **World 6** (id 6, "QA World", turn ~2528 at brief time): QA user is
  **player 1**, city **1 "Oakhaven"** at tile **21635**, size 4, food
  70-90, territory 10 tiles. Warrior **unit 23** (HP 100) is garrisoned
  directly ON tile 21635 right now — ready-made for 7471 (finished unit
  must land adjacent, not on the occupied city tile). Do not touch
  other players' units/cities in world 6 (`johns10@gmail.com`'s real
  account, or the `qa877-throwaway2` fixture) — only player 1 is in
  scope. City 1 is size 4, not size 1 — do NOT use it for the flat-8-turn
  numeric claim (7468); a size-4 city with worked tiles banks faster
  than 5/turn. Use it only for 7471 (occupied-tile spawn) and optionally
  7472's code-verified fallback.
- **World 1** (id 1, "Jade Wilds", turn ~2606 at brief time): QA user is
  **player 10**, with an untouched **settler (unit 20, tile 6526)** and
  **lord (unit 19, tile 6569)** — no city founded yet. Found a fresh
  size-1 city here for the numeric/banking criteria (7467, 7468, 7469,
  7470, 7473) — a clean subject with no worked tiles or existing queue.
  Confirm the settler's tile terrain (sidebar, or psql
  `BrokenOaths.Worlds.Regions.terrain/2` via a pure — non-Game — probe)
  is land before founding.
- Turn boundary is 60s wall-clock. Grab the current turn via
  `psql broken_oaths_dev -c "SELECT id, turn, turn_started_at FROM worlds WHERE id IN (1,6);"`
  before queuing anything, then track `banked`/`cost` in
  `game_production_items` across boundaries via psql rather than
  eyeballing the progress bar, to get exact turn deltas.
- **Never call `BrokenOaths.Game.*` from a second `iex`/`mix run`
  process** while the dev server runs — competing `WorldServer` risk.
  `Worlds`/`Globe`/`Terrain`/`Regions` calls are pure and iex-safe.
  psql and vibium both need the sandbox disabled.

## What To Test

- **7467 (catalog is exactly Settler/Worker/Warrior with costs, no
  Monument)** — on world 1:
  1. Log in, go to `/play/1`.
  2. Confirm settler unit 20's tile (6526) is land via a pure probe.
  3. Push `found_city` with `unit_id: 20` via the hook technique (and,
     per the note above, try the real DOM equivalent once you have a
     city panel open, to establish ground truth on the known bug).
  4. Select the new city (`select_city`), screenshot
     `[data-test='city-panel']`.
  5. Confirm `[data-test='production-option-settler']` shows cost 100,
     `[data-test='production-option-worker']` shows 60,
     `[data-test='production-option-warrior']` shows 40, and no
     `[data-test='production-option-monument']` element exists.
  6. Note: `Production.can_queue?/2` disables the Settler option outright
     on a size-1 city (`{:error, :size_one}`) — the button should still
     be *present* with cost 100, just disabled
     (`data-disabled="true"`), with
     `[data-test='production-disabled-reason-settler']` visible. This
     is a supporting fact for story 883, not a 7467 fail condition —
     7467 only asks about which items are offered and at what cost.

- **7468 (warrior completes after exactly 8 turns of flat banking) +
  7469 (progress reads as banked/cost mid-build)** — same world-1 city:
  1. Note the current turn (`turn0`) via psql.
  2. Queue a Warrior (`queue_production`, `item: "warrior"`).
  3. Confirm via psql `game_production_items` a row exists:
     `type='warrior', banked=0, cost=40`.
  4. Screenshot the city panel: `[data-test='city-production-current']`
     should read "Warrior 0/40"; `[data-test='city-production-progress']`
     should have `value=0 max=40`.
  5. Wait for one turn boundary (poll psql `worlds.turn` every ~15s
     until it increments past `turn0`). Confirm `banked` is now 5
     (flat base, no worked tiles on a freshly founded city).
  6. Screenshot again mid-build (e.g. after 3-4 boundaries, banked ~15-20)
     — cross-check the UI's `X/Y` text and progress bar `value` against
     the psql `banked`/`cost` at that same instant (7469).
  7. Continue polling. At turn0+7 boundaries, confirm `banked = 35` and
     no warrior unit exists yet for player 10 (psql `game_units`). At
     turn0+8, confirm `banked` reaches 40 and completes: the
     `game_production_items` row for this item should be gone (or the
     queue empty) AND a new `game_units` row with `type='warrior'`
     should exist for player 10. This nails 7468's "exactly eight, not
     seven, not nine" claim.

- **7470 (queue rolls into the next item, overflow carries)** — same
  world-1 city, immediately after 7468/7469 (reuse the same warrior
  build, or start a fresh one if it's more convenient):
  1. Before the warrior completes (any point banked > 0), queue a
     second item behind it, e.g. Worker (`queue_production`,
     `item: "worker"`, cost 60). Confirm via psql two
     `game_production_items` rows exist for the city, ordered
     warrior-then-worker.
  2. Let the warrior complete (per 7468's steps). Since a freshly
     founded size-1 city with no worked tiles banks exactly 5/turn and
     40 is an exact multiple of 5, overflow will land on an exact
     boundary with **zero** remainder by construction — confirm this
     honestly (worker's `banked` should be exactly 0 right after the
     warrior completes, not a bug). If you want to observe *nonzero*
     carry-over concretely, assign a worked tile to the city first (any
     `[data-test='city-worked-tile-<id>']`/assignable-tile "Work"
     button in the panel, once the city has grown past size 1 — check
     `[data-test="city-size"]`) so the per-turn rate stops being a
     multiple of 40; this may not fit the time-box, in which case note
     the zero-remainder case as verified and point to
     `criterion_7470_..._spex.exs` (already engineers a nonzero-overflow
     fixture) as the corroborating unit-level proof for the nonzero
     path specifically.
  3. Confirm via psql/UI: after the warrior completes, the queue's head
     is now the Worker (`[data-test='city-production-current']` reads
     "Worker X/60"), and the Worker did not reset to a fresh empty
     queue entry — it inherited whatever came from the warrior's
     overflow.

- **7473 (reordering is free; abandoning mid-build forfeits the
  investment)** — same world-1 city, fresh queue state (or continue
  from 7470's Worker):
  1. With 2+ items queued, if a reorder affordance exists in the UI,
     use it and confirm via psql that reordering does not change any
     item's `banked` value (free action). If no drag/reorder UI exists
     in `CityPanel` (source review suggests queue order is FIFO/no
     reorder UI — confirm by reading `city_panel.ex` again if unsure),
     note that as a finding: the criterion implies reordering should be
     possible, but this may need to be verified against the actual
     acceptance criteria text/BDD spec rather than assumed.
  2. Queue a Settler (needs size >= 2 — grow the city first, or use
     Worker/Warrior if size is still 1) and let it bank partway (any
     nonzero `banked` less than `cost`). Note the exact `banked` value
     via psql.
  3. Cancel that in-progress item via `cancel_production_item` (real
     button `Cancel` next to a queued, non-head item — note per
     `city_panel.ex` only NON-head queue items render a `Cancel`
     button in `.queue_item`; the head item has no cancel affordance in
     the current markup, only via `cancel_production_item` pushed
     directly). Confirm via psql the `game_production_items` row is
     gone and the banked production is NOT transferred anywhere (not
     to the next item, not refunded) — genuinely forfeited.
  4. Screenshot before/after.

- **7471 (finished unit lands beside an occupied city tile)** — world 6,
  city 1 "Oakhaven" (already has warrior unit 23 garrisoned on the
  city's own tile 21635):
  1. Note current turn (`turn0`) via psql.
  2. Queue a Worker or Warrior in Oakhaven (`queue_production`,
     city_id: 1). Confirm via psql the item exists.
  3. Poll until it completes (check `game_units` for a new unit owned
     by player 1 not previously present).
  4. Confirm the new unit's `tile_id` is NOT 21635 (occupied by unit 23)
     but IS one of tile 21635's adjacent land tiles (per
     `Production.landing_tile/3`'s candidate order: city tile first,
     then adjacent land tiles in `Regions.adjacent_tiles/2` order,
     first unoccupied). Screenshot the board/city panel showing both
     units.

- **7472 (a completely blocked city holds the finished unit without
  losing it)** — time-box live setup to ~15 minutes given the
  multi-player blockade this requires (see
  `criterion_7472_..._spex.exs` for the full recipe: find the
  minimum-land-neighbor tile, queue three players' worth of units onto
  every neighbor plus the city tile itself). If a live repro isn't
  practical in the time-box with just the QA account (no second/third
  player readily available without seeding new accounts), fall back to
  reading `BrokenOaths.Game.Production.complete/3` /
  `resolve_completions/1` in `lib/broken_oaths/game/turn.ex` and
  `lib/broken_oaths/game/production.ex` (already read while writing
  this brief — `landing_tile/3` returns `nil` when every candidate tile
  is occupied, and `complete_loop/4` simply stops without touching
  `queue`/`banked` when that happens — so a blocked completion provably
  loses nothing structurally). Report explicitly whether this was
  exercised live or code-verified-only; do not skip the criterion
  silently either way.

## Result Path

Findings are filed via `create_issue` as discovered (not written to a
result file); the QA run concludes with one `submit_qa_result` call
against task id `179df1a9-166e-4009-89ca-139e6d6c0c85`. Screenshots go
in `.code_my_spec/qa/879/screenshots/`, raw psql evidence in
`.code_my_spec/qa/879/responses/`.

## Setup Notes

- Dev server is already running at `http://localhost:4050` — do not
  restart it, do not run `mix phx.server`/`mix compile`/`mix format`/
  `mix test`/`mix spex` (any out-of-band compile risks the "you must
  restart your server" 500 documented in `.code_my_spec/qa/plan.md`).
- `psql broken_oaths_dev` and `vibium` both require the sandbox
  disabled (`dangerouslyDisableSandbox: true`).
- Turn boundary is 60s wall-clock. 7468 alone needs 8 boundaries
  (~8 minutes minimum) to observe honestly; interleave other
  scenarios (7467 catalog check, 7471 in world 6) while polling.
- Do not file a duplicate issue for the known
  `found_city`/`queue_production`/`cancel_production_item` parse bug —
  reference `a1c8741d-a889-409c-aad6-d17166e7e7b0` instead. If live
  testing shows the bug is actually already fixed (source strongly
  suggests this — see the Auth section above), say so plainly in the
  scenario observations and consider whether `a1c8741d` should be
  flagged for re-triage, but do not unilaterally resolve someone else's
  filed issue without solid reproduction evidence either way.
- City ids, unit ids, and final state (whatever you leave behind in
  worlds 1 and 6) matter to downstream stories 880-883 — be precise in
  the final report about exactly which city/unit ids exist and what's
  queued/completed when you stop.
