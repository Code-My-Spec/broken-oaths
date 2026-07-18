# Qa Plan

## App Overview

Broken Oaths is a Phoenix 1.8 / LiveView 1.1 / Ecto (Postgres) hex-globe
strategy game with a single router and a single endpoint listening on
**http://localhost:4050** (dev; the `PORT` env var overrides).
Authentication is session-based via phx.gen.auth magic-link login with
an optional password form — no API tokens, no MCP transports; the only
`:api` pipeline is defined but unused. Route groups: public browser
routes (`/`, `/worlds`, `/worlds/:id`, `/worlds/:id/{texture,airspace}.png`,
auth pages), an authenticated live_session (`/users/settings`,
`/accounts*`, `/integrations`), an authenticated OAuth controller scope
(`/integrations/oauth/:provider`), and dev-only routes
(`/dev/dashboard`, `/dev/mailbox`, `/dev/qa/worlds/:id/*` — the QA
control surface, see Tools Registry below). Probed status codes: public routes
200; authenticated routes 302 → `/users/log-in`; `/health` and `/up`
answer 200 from an endpoint plug ahead of the router (used by
kamal-proxy and UptimeRobot in deployed envs).

## Tools Registry

### Vibium (browser — LiveView pages)

Use for every LiveView flow: login, world browsing, the globe board,
account management. The vibium CLI drives a persistent Chrome; MCP
browser tools may also be present depending on session.

    vibium go "http://localhost:4050/users/log-in"
    vibium find "#login_form_password" 2>/dev/null
    vibium screenshot   # writes ~/Pictures/Vibium/screenshot.png

Probed login selectors (two forms render on one page):

- Magic link: `#login_form_magic` with `input[name="user[email]"]`
- Password: `#login_form_password` with `input[name="user[email]"]`,
  `input[name="user[password]"]`, checkbox `user[remember_me]`

Game board specifics: `/worlds/:id` defaults to the 3D canvas globe
(zero tile DOM — assert via LiveView pushes in tests, or visually via
screenshots). Append `?mode=classic` for the selector-testable DOM
board where every tile is `[phx-value-id='<tile_id>']`. Camera is
URL-driven: `?yaw=<deg>&pitch=<deg>&zoom=<px>` composes with either
mode. After vibium restarts, always re-`vibium go` — it often lands on
about:blank; if commands hang: `pkill -f chrome-for-testing; pkill -x
vibium; rm -f ~/Library/Caches/vibium/vibium.sock`.

### curl (public controller endpoints)

Use for the texture endpoints and health. No auth needed on these.

    curl -s -o /dev/null -w "%{http_code}" http://localhost:4050/worlds/6/texture.png
    curl -s -o /dev/null -w "%{http_code}" http://localhost:4050/worlds/6/airspace.png
    curl -s http://localhost:4050/health

There is no header/token auth surface in this app: authenticated routes
use the session cookie, and the login POST requires a CSRF token — use
Vibium for anything behind `require_authenticated_user` rather than
scripting cookie jars.

### curl (dev-only QA control surface — `BrokenOathsWeb.DevQaController`)

Dev-gated (mounted only inside `router.ex`'s `dev_routes` compile_env
block — same gate as LiveDashboard; never exists in a prod build), no
auth, rooted at `/dev/qa/worlds/:id`. Lets a QA agent construct and
control a live multiplayer scenario deterministically — most
importantly, pause the turn clock so staged units never die to
catch-up/AI before you act, then step turns on demand. See the
"Deterministic multiplayer QA" recipe below.

| Method | Path | Body params | What it does |
|---|---|---|---|
| GET    | `/dev/qa/worlds/:id`               | —                             | `{id, turn, turn_seconds, paused}` |
| POST   | `/dev/qa/worlds/:id/pause`          | —                             | Freeze the turn clock |
| POST   | `/dev/qa/worlds/:id/resume`         | —                             | Unfreeze the turn clock (resets the current turn's clock, no catch-up owed) |
| POST   | `/dev/qa/worlds/:id/step`           | —                             | Advance exactly one turn — works even while paused |
| POST   | `/dev/qa/worlds/:id/units`          | `player_id, type, tile_id`    | Spawn a player-owned unit (`type`: warrior/worker/settler/lord) |
| POST   | `/dev/qa/worlds/:id/barbarians`     | `tile_id, camp_id?`           | Spawn a barbarian warrior (`camp_id` optional — ties it to a real camp's AI) |
| PATCH  | `/dev/qa/worlds/:id/units/:unit_id` | `hp?, tile_id?, recharge?`    | Any combination: set HP, relocate, and/or recharge movement |
| DELETE | `/dev/qa/worlds/:id/units/:unit_id` | —                             | Hard-delete a unit (e.g. clear a camp's garrison) |
| PATCH  | `/dev/qa/worlds/:id/camps/:camp_id` | `hp`                          | Set a camp's HP directly |

Example calls:

    curl -X POST http://localhost:4050/dev/qa/worlds/1/pause
    curl http://localhost:4050/dev/qa/worlds/1
    curl -X POST http://localhost:4050/dev/qa/worlds/1/units \
      -d player_id=3 -d type=warrior -d tile_id=120
    curl -X POST http://localhost:4050/dev/qa/worlds/1/barbarians -d tile_id=121
    curl -X PATCH http://localhost:4050/dev/qa/worlds/1/units/42 -d hp=10
    curl -X PATCH http://localhost:4050/dev/qa/worlds/1/units/42 -d tile_id=121
    curl -X DELETE http://localhost:4050/dev/qa/worlds/1/units/42
    curl -X PATCH http://localhost:4050/dev/qa/worlds/1/camps/7 -d hp=1
    curl -X POST http://localhost:4050/dev/qa/worlds/1/step
    curl -X POST http://localhost:4050/dev/qa/worlds/1/resume

`player_id`/`camp_id`/`unit_id` are the real DB ids — read them off a
`GET /dev/qa/worlds/:id`-adjacent read (there's no listing endpoint
here by design; find ids via the browser's own state pushes, or
`psql broken_oaths_dev` for a one-off lookup) or capture them from a
prior `POST .../units` / `POST .../barbarians` response, which returns
the full spawned unit (`id`, `tile_id`, `hp`, ...).

### mix run (seeds and setup)

    mix run priv/repo/qa_seeds.exs

Boots the app once, runs all seed logic in-process, prints credentials
and URLs (see Seed Strategy).

### iex (state inspection during a QA session)

    iex -S mix

Then e.g. `BrokenOaths.Worlds.list_worlds()` to find world ids, or
`BrokenOaths.Worlds.Weather.map(seed, BrokenOaths.Worlds.Globe.get(54))`
to locate storm tiles for weather QA. Prefer asserting through the UI;
use iex to *find* things, not to *prove* things.

**During QA sessions: do not run `iex -S mix`, `mix run`, or
`mix run -e` AT ALL — not even for "pure" reads.** Any mix invocation
from a second shell can trigger a recompile that kills or wedges the
running dev server (observed 2026-07-16: a "safe" `mix run -e` read
took the server process down entirely mid-QA). Read state via
`psql broken_oaths_dev` or the browser, full stop. The earlier,
narrower warning below is kept for context:

**Never call `BrokenOaths.Game.*` from a separate `iex -S mix` /
`mix run` process while the dev server is running.** Those functions
route through a per-node `WorldServer` GenServer — a second BEAM node
lazily starts its own competing instance for the same world, whose
boot-time catch-up races the live server's turn writes (issue
07ee50d1). The turn write is now optimistically guarded so the row can
no longer be corrupted (the loser resyncs), but the rogue instance
still ticks and burns writes. `Worlds.*` / `Globe` / `Weather` /
`Regions` / `Terrain` calls are pure and safe. For unit/turn/order
state, read the DB directly (`psql broken_oaths_dev`) or go through
the browser.

## Seed Strategy

Single Ecto repo (`BrokenOaths.Repo`, Postgres, database
`broken_oaths_dev` in dev). One seed script covers all current QA
scenarios:

- **`priv/repo/qa_seeds.exs`** — run with `mix run priv/repo/qa_seeds.exs`.
  Idempotent (safe to re-run; reuses existing records). Creates:
  - QA user `qa@broken-oaths.test`, confirmed via the real magic-link
    flow, with password `qa-password-123!` — works in the
    `#login_form_password` form.
  - "QA World" (seed 424242, frequency 54 = 29,162 tiles) — a
    deterministic globe so terrain/weather facts are stable across
    machines. Has ~104 spawnable regions (`Regions.spawnable/1`'s
    175-tile habitability floor) — too many to fill by hand through
    the browser.
  - "QA World (Fill Test)" (seed 111222, frequency 8 = 642 tiles,
    world id 10 as of this writing) — resolves to exactly **two**
    spawnable regions, added for story 873 QA. Lets a tester fill the
    world with two throwaway joins and then exercise "world just
    filled up" / abandon-and-reclaim scenarios without scripting
    dozens of accounts.
  - Prints: credentials, world URLs (globe + classic mode), the
    fill-test world URL, and the dev mailbox URL.
  - **Do not seed worlds at frequency 5-6.** They reliably trigger a
    Spawner crash (issue `6b8a69f3-d401-4cb7-b45f-ad3ceaf414e6`): a
    `:land` tile fully enclosed by same-region `:mountain` tiles has
    no BFS path to the region boundary, and `Spawner.central_land_tiles/2`
    raises `KeyError`. This crashes `world_full?/1`, which crashes the
    entire `/play` picker for **every** world, not just the bad one —
    it's a full outage of the join page as long as any `status:
    "active"` world has this terrain shape. World id 7, "QA World
    (Full Test)" (frequency 5, seed 500555), is deliberately left
    `status: "archived"` in the DB as a standing repro case — do not
    reactivate it. Every seed frequency tried at 7-8 was crash-safe in
    a spot-check across ten seeds; re-verify per-region safety with a
    dry-run probe (see the story 873 QA session) before introducing
    another low-frequency world.

For magic-link testing specifically: submit `#login_form_magic` with
any seeded email, then read the link from **http://localhost:4050/dev/mailbox**
(Swoosh local adapter — no real email leaves the box).

The stock `priv/repo/seeds.exs` is empty; `mix ecto.setup` runs it as
part of database creation but seeds nothing.

## System Issues

### Dev server needs a restart after out-of-band compiles

The Phoenix code reloader shares `_build/dev` with any shell that runs
`mix compile`/`mix format`. After config file changes (or agent-driven
compiles), the running server starts returning 500 on every routed path
with "You must restart your server after changing configuration files"
— while `/health` still answers 200 (it's an endpoint plug ahead of the
router, so it masks the failure from naive monitoring). Workaround:
kill by port, NEVER by pattern — `kill $(lsof -ti :4050)` — then
restart. A broad `pkill -f "mix phx.server"` matches every Phoenix
project's dev server on the machine (observed 2026-07-16: our server
was SIGTERM'd as collateral from exactly such a pkill, likely from a
session working on a different project). Status: open — recurred three
times in one session.

### Vibium screenshot path argument is ignored

`vibium screenshot <path>` fails with "failed to navigate: invalid
argument" on this box; plain `vibium screenshot` works and always
writes `~/Pictures/Vibium/screenshot.png`. Copy it aside if you need to
keep frames. Status: open.

### Sandbox blocks writes under config/

Agent shells sandboxed by Claude Code cannot write `config/*` via
python/bash (Operation not permitted) — use the file-edit tools
instead. Status: open (environmental, not an app bug).

### Sandbox blocks the vibium daemon socket

`vibium go`/`vibium daemon start` fail with "socket not available after
5s" under the default Claude Code sandbox — the daemon's socket lives
under `~/Library/Caches/vibium/`, which isn't in the sandbox's writable
path allowlist (only `~/.cache`, `~/.npm`, `~/.mix`, etc. are). Run
vibium commands with the sandbox disabled for this session (bash tool
`dangerouslyDisableSandbox: true`) rather than retrying in-sandbox.
Status: open (environmental, not an app bug).

## Deterministic Multiplayer QA (pause → spawn/position/heal → step → assert)

The live `WorldServer` runs a real wall-clock turn timer and barbarian
AI — staged units can die to catch-up/AI before a tester acts unless
the clock is frozen first. Recipe for any multiplayer flow (e.g. story
901 cooperative combat / alliances):

1. **Pause**: `curl -X POST .../dev/qa/worlds/:id/pause`. Confirm with
   `curl .../dev/qa/worlds/:id` (`"paused": true`). Nothing on the
   board changes on its own from here on — `advance_turn` (the `/step`
   endpoint) is the ONLY thing that moves the clock.
2. **Construct the scenario**: spawn player units for each account
   under test (`POST .../units` — needs each account's `player_id`,
   read via the browser session or `psql`), spawn/position barbarians
   (`POST .../barbarians`), heal or relocate existing units (`PATCH
   .../units/:unit_id`), clear an inconvenient garrison (`DELETE
   .../units/:unit_id`), or pre-damage a camp (`PATCH
   .../camps/:camp_id`). Every write here is synchronous and
   immediately visible — no turn boundary required.
3. **Drive the actual UI/browser flow under test** (Vibium) against
   this now-fully-controlled board — click, attack, propose/accept
   alliances, whatever the story needs.
4. **Step turns on demand**: `POST .../dev/qa/worlds/:id/step` advances
   exactly one turn (production accrual, barbarian AI, healing, etc.)
   without waiting out the real `turn_seconds` countdown, and without
   any of the OTHER missed-time replay a real dormant boot would do.
   Repeat as needed between assertions.
5. **Resume** (`POST .../dev/qa/worlds/:id/resume`) only once the
   scripted portion of the scenario is done and you want the world
   back on its normal live cadence — resuming resets the turn clock so
   the world doesn't immediately "owe" a catch-up for the paused
   interval.

`paused` is persisted on the `worlds` row, so a paused QA world stays
frozen even across a dev server restart (mid-`mix compile`, a crash,
etc.) — no need to re-pause after every restart mid-session.

## Notes

The canvas globe cannot be asserted pixel-by-pixel; the truth surfaces
are (a) LiveView push events (`globe3d:window`, `globe3d:selected`,
`globe3d:airspace`) assertable in LiveViewTest, (b) the classic-mode
DOM, and (c) the sidebar HTML (tile id, terrain label, camera
readout — open it first with the `toggle_sidebar` button; it's
collapsed by default). Weather QA: storm tiles flash lightning every
few seconds at any zoom; find storm coordinates via iex
(`Weather.map/2`, level 3 entries) and aim the camera with URL params.
Deployed environments mirror dev: https://uat.broken-oaths.com (UAT
box) and https://broken-oaths.com (prod) — same routes, seeds must be
run through a release shell (`kamal app exec`), not against them from
here.
