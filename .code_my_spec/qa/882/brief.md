# Qa Story Brief

Story 882 — Worker Improves Terrain.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Password form `#login_form_password`: `input[name="user[email]"]`,
  `input[name="user[password]"]`, submit via
  `#login_form_password button[name='user[remember_me]']`.
- Primary account (world 6, "QA World"): `qa@broken-oaths.test` /
  `qa-password-123!`.
- World 10 ("QA World (Fill Test)") accounts have no password —
  authenticate via magic link: submit `#login_form_magic` with
  `input[name="user[email]"]`, then read the link from
  `http://localhost:4050/dev/mailbox` (Swoosh local adapter). Must log
  out (`a[href='/users/log-out']`) before switching accounts, or the
  email field renders readonly in re-auth mode.
  - `throwaway1@example.test` (player 3, city 2 "City 1" @ tile 638)
  - `qa873-fillb@broken-oaths.test` (player 11, city 3 "City 1" @ tile 606)
- Driven with the `vibium` CLI directly (bash tool, sandbox disabled).
  Key commands: `vibium go <url>`, `vibium fill <selector> <text>`,
  `vibium click <selector>`, `vibium map --selector <selector>`,
  `vibium eval <js>`, `vibium screenshot` (always writes
  `~/Pictures/Vibium/screenshot.png` — copy aside per scenario).
- The board (`/play/:id`) is canvas-only. City selection is driven via
  the live LiveView socket (same code path as a real click):

      window.liveSocket.owner(document.getElementById('board-viewport'), view => {
        const hook = view.viewHooks[Object.keys(view.viewHooks)[0]];
        hook.pushEvent('select_city', {city_id: <id>});
      });

  Once a city/unit is selected this way, the resulting
  `[data-test='city-panel']` / `[data-test='unit-panel']` are real DOM
  elements — click/fill those directly to exercise the actual DOM
  wiring (confirmed working for production buttons as of commit
  cc0b599 — the string/integer id bug from stories 878/879 is fixed).

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent, already current. **IMPORTANT: per the hardened QA rule from
this batch, do NOT run this or any other `mix`/`iex` command during
execution — a second `mix`/`iex` process recompiles the shared
`_build/dev` and has twice crashed the running dev server this
session.** Seeds are already applied; psql and the browser only from
here.

State re-verified via psql immediately before writing this brief:

- World 6 (id 6): Oakhaven (city 1, player 1/QA user, tile 21635,
  size 4). Worker queued (`game_production_items` id 10, banked
  18/60 already, fast rate).
- World 10 (id 10): city 2 "City 1" (player 3/throwaway1, tile 638,
  size 4, territory `{491,495,634,635,637,638,640,492,488,482}`) and
  city 3 "City 1" (player 11/qa873-fillb, tile 606, size 4, territory
  `{600,601,606,607,611,622,623,612,616,617}`) — founded at minimum
  legal spacing during story 878's QA, so genuinely close together in
  this tiny (freq 8) world. Worker queued for city 2
  (`game_production_items` id 11, banked 0/60 at queue time).
  These two cities' proximity is the vehicle for testing "a worker
  helps a friend by farming their land" (7483) without needing extra
  turns to walk cross-world.
- No hills tiles confirmed reachable in world 6 as of the prior (880)
  session; hills availability in world 1/10 unconfirmed — terrain
  can no longer be probed via a pure `iex`/`mix run` call under the
  hardened rule, so the Mine criterion (7485) will be tested for UI
  option-gating live (mine button disabled off-hills) and, if no
  reachable hills tile turns up within a reasonable time-box, backed
  by reading the improvement-building source rather than faking a
  live completion.

## What To Test

- **7481 (a worker is a builder, not a fighter):** once either worker
  completes, open its unit panel — confirm HP is 1 (not the
  warrior's 100), confirm there is no attack/combat action available,
  only movement + build-improvement actions.
- **7482 (three turns of digging turns grassland into a farm):** move
  a worker onto grassland/plains it doesn't already own an
  improvement on, click the Farm build action, track
  `game_improvements.progress` via psql across three consecutive 60s
  turn boundaries, confirm completion at exactly turn 3 and that the
  tile flips to a farm improvement.
- **7483 (a worker helps a friend by farming their land):** walk
  city 2's worker (once produced) into city 3's territory (or vice
  versa — whichever is closer) and build a farm there. Confirm the
  improvement's owning city (via `game_improvements`/yield
  attribution) is the tile-owner's city, not the worker's own
  civilization. This can double as the 7482 timing test if the
  target tile is grassland/plains.
- **7484 (an abandoned dig waits patiently for the next shovel):**
  start a build, move the worker away before completion (or produce
  a second worker and reassign the first), confirm via psql the
  `game_improvements` row persists at partial `progress` with a
  resumable status, then bring a worker back and confirm progress
  continues rather than resetting to 0.
- **7485 (a finished mine pays its city and refuses a second
  improvement):** find a hills tile reachable by a worker (explore via
  the build-mine button's enabled/disabled state as a live terrain
  oracle, since direct terrain queries are off-limits this session).
  If found: build the mine, confirm on completion the city's
  production yield reflects it and a second improvement attempt on
  the same tile is refused. If no hills tile is reachable within a
  ~15 minute time-box, verify option-gating live on the tiles that
  are reachable (mine correctly disabled off-hills) and fall back to
  reading `lib/broken_oaths/game/production.ex` (or wherever
  improvement completion is implemented) for the pay-city and
  refuse-second-improvement logic, noting explicitly that the
  completion path is code-verified-only in that case.

## Result Path

`.code_my_spec/qa/882/screenshots/` for evidence; canonical result via
`submit_qa_result` (task id from `start_task`), no result.md.

## Setup Notes

Second dev-server crash of this QA batch happened between stories 881
and 882 (external SIGTERM per team lead, unrelated to any QA session).
Server and MCP plugin both confirmed healthy again before this story
started. Real production/city buttons confirmed fixed (commit cc0b599)
— use them directly rather than the hook-eval workaround wherever
possible, and note explicitly in results when they work.
