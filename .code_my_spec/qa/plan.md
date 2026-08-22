# Qa Plan

## App Overview

Broken Oaths is a Phoenix 1.8 / LiveView 1.1 / Ecto (Postgres) hex-globe
strategy game with a single router and a single endpoint listening on
**http://localhost:4050** (dev; the `PORT` env var overrides).
Authentication is session-based via phx.gen.auth magic-link login with
an optional password form for end users; the `:api` pipeline is now
also live under `/api/cms/users` (`CmsUsersController`), authenticated
by a deployment-key Bearer token rather than a user session — see
Tools Registry below. Route groups: public browser routes (`/`,
`/worlds`, `/worlds/:id`, `/worlds/:id/{texture,airspace}.png`, auth
pages), the `/api/cms` deploy-key API, an authenticated live_session
(`/users/settings`, `/accounts*`, `/integrations`, `/play`, `/play/:id`),
an authenticated OAuth controller scope (`/integrations/oauth/:provider`),
and dev-only routes (`/dev/dashboard`, `/dev/mailbox`, `/dev/qa/worlds/:id/*`
— the QA control surface, see Tools Registry below). Probed status codes: public routes
200; authenticated routes 302 → `/users/log-in`; `/health` and `/up`
answer 200 from an endpoint plug ahead of the router (used by
kamal-proxy and UptimeRobot in deployed envs).

## Tools Registry

### Vibium (browser — LiveView pages)

Use for every LiveView flow: login, world browsing, the globe board,
account management. **Prefer the `vibium` CLI over the MCP `browser_*`
tools** — see "MCP browser tools are unreliable" under System Issues
below before relying on the MCP tools for anything multi-step.

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
| POST   | `/dev/qa/worlds/:id/reload`         | —                             | Restart the live `WorldServer`, force-rehydrating from the DB — pairs with a raw-`Repo` reseed so the running server picks up the fresh state |
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

`step` advances the raw turn counter, but production/science/gold
("economy") only accrues once every `world.economy_turns` raw turns
(default 10 — `Simulation.Turn`'s own moduledoc, `economy_tick?/2`),
same for movement recharge every `world.recharge_turns`. Stepping once
and checking a queue's `banked` immediately after will look like
nothing happened unless the new turn happens to land on an economy
boundary. For a QA session that needs to watch a build actually
complete turn-by-turn (e.g. comparing two units' completion speed),
either step all the way to the next multiple of `economy_turns`, or —
much faster — drop that one world's `economy_turns` to `1` for the
session (`UPDATE worlds SET economy_turns = 1 WHERE id = ...` via
`psql`, then `POST .../reload` to pick it up) and put it back to `10`
afterward so other sessions relying on the original pacing aren't
affected (story 952 QA, 2026-08-21).

`player_id`/`camp_id`/`unit_id` are the real DB ids — read them off a
`GET /dev/qa/worlds/:id`-adjacent read (there's no listing endpoint
here by design; find ids via the browser's own state pushes, or
`psql broken_oaths_dev` for a one-off lookup) or capture them from a
prior `POST .../units` / `POST .../barbarians` response, which returns
the full spawned unit (`id`, `tile_id`, `hp`, ...).

### Deterministic multiplayer QA recipe (pause → spawn/position/heal → step → assert)

The live `WorldServer` runs a real wall-clock turn timer and barbarian
AI — staged units can die to catch-up/AI before a tester acts unless
the clock is frozen first. Recipe for any multiplayer flow (e.g. story
901 cooperative combat / alliances), built entirely from the
DevQaController endpoints above:

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
3. **Drive the actual UI/browser flow under test** (Vibium, or
   `board_click.sh`/`board_state.sh` below for the canvas board)
   against this now-fully-controlled board — click, attack,
   propose/accept alliances, whatever the story needs.
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

### curl (`/api/cms/users` — deploy-key API, CodeMySpec dashboard read model)

`BrokenOathsWeb.CmsUsersController`, authenticated by
`Authorization: Bearer <DEPLOY_KEY>` (matching `:broken_oaths,
:deploy_key` config) — NOT a user session, this is the credential
CodeMySpec's own content sync uses. Read-only, paginated
(`page`/`page_size`, default 50 / max 100). Missing/bad key returns
`401 {"error": "Invalid deployment key"}` (or `"Missing deployment
key"`); success returns `{data: [%{email:, registered_at:}...], page,
page_size, total}`.

    curl -sS http://localhost:4050/api/cms/users -H "Authorization: Bearer $DEPLOY_KEY"
    curl -sS "http://localhost:4050/api/cms/users?page=2&page_size=10" -H "Authorization: Bearer $DEPLOY_KEY"

### Canvas board interaction — `.code_my_spec/qa/scripts/board_click.sh` / `board_state.sh`

`GameLive.Play`'s board (`/play/:id`) is canvas-only — no tile DOM, no
`[phx-value-id]`-style selector to click (see `play.ex`'s own
moduledoc). These two scripts drive it through the live LiveView hook
instance instead of the DOM:

- **`board_state.sh [tile_id]`** — dumps the hook's client-side state
  as JSON: own units (id/type/tile_id/hp/movement/order), visible
  camps, visible cities, the selected unit id, and the full fog-known
  tile id list. With a `tile_id` arg, also computes that tile's
  neighbor ids among the currently-known set (a client-side stand-in
  for the server's real adjacency, using the corner-geometry the
  server already pushes over `game:window`). Use this FIRST to find
  valid tile ids and check real adjacency before targeting a click.
- **`board_click.sh <tile_id> <left|right>`** — reaches into
  `window.liveSocket.main.viewHooks`, projects the given tile's center
  to screen coordinates the same way the client projects for
  painting, and dispatches a synthetic PointerEvent there. Left click
  selects the unit/city/tile on that tile; right click queues a move,
  or issues an attack order if a hostile unit/camp occupies that exact
  tile. `tile_id` must be one already in the fog window (`board_state.sh`
  lists them).

Requires: Vibium already navigated to `/play/:id` (run with the
sandbox disabled — see System Issues). Both scripts document a known
pointer-tracking QA issue (e25fb72f) inline; read the script headers
before use if a click/drag sequence behaves unexpectedly.

    ./.code_my_spec/qa/scripts/board_state.sh
    ./.code_my_spec/qa/scripts/board_state.sh 14741
    ./.code_my_spec/qa/scripts/board_click.sh 14741 left
    ./.code_my_spec/qa/scripts/board_click.sh 14741 right

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

- **`priv/repo/qa_seeds_multiplayer.exs`** — run with
  `mix run priv/repo/qa_seeds_multiplayer.exs`. Idempotent AND
  self-healing (re-running repairs drift, doesn't just skip). Builds
  on `qa_seeds.exs`'s patterns to stage story 901 (Cooperative
  Barbarian Fighting) and general two-player scenarios: two confirmed
  QA players, joined and founded in a FAST-turn world
  (`turn_seconds: 5`), each with a real warrior standing adjacent to
  the SAME barbarian camp — ready for an immediate cooperative assault
  through the browser, no manual setup required. Mutual discovery is
  pre-seeded so chat/alliance panels are unlocked from the first page
  load. Because `turn_seconds: 5` is fast, the world's wall-clock
  catch-up can fire real camp-spawn/barbarian-AI ticks between runs;
  the script unconditionally resets camps/barbarians/city HP/warrior
  position via raw `Repo` writes every time it runs rather than
  fighting that mechanic — safe to re-run any time state looks off.
- **`priv/repo/qa_seeds_rebellion.exs`** — run with
  `mix run priv/repo/qa_seeds_rebellion.exs`. Idempotent and
  self-healing; builds on `qa_seeds_multiplayer.exs`'s patterns. Boots
  ONE world into the staged state the 4-beat rebellion demo
  (`.code_my_spec/qa/rebellion_demo_plan.md`) needs, doubling as the
  per-story QA journeys for stories 913-919. Three actors: a DEMO
  PLAYER (lord of a fresh vassal, then vassal of a strained NPC
  tyrant), a RIVAL PLAYER (independent, one city, HP forced low and a
  demo warrior staged adjacent for a live one-hit siege), and an NPC
  TYRANT LORD built by direct `Repo` insert (never logs in, anchors
  the world's one non-spawnable "wilderness" region). Diverges from
  `qa_seeds_multiplayer.exs` in three load-bearing ways: the world
  boots PAUSED (no wall-clock catch-up fight needed at all — use the
  `/dev/qa/worlds/:id` pause/step/resume surface above to drive turns
  instead), the NPC tyrant is a direct-insert non-spawnable actor, and
  one city is hand-marked "occupied" to satisfy a precondition the
  rebellion mechanic itself enforces. Prints credentials, world URL,
  and a full beat-by-beat "what to click" walkthrough — including a
  "dismiss the Oath screen first" step needed before recording, since
  the demo player's board opens on the Terms-of-Oath prompt.

For magic-link testing specifically: submit `#login_form_magic` with
any seeded email, then read the link from **http://localhost:4050/dev/mailbox**
(Swoosh local adapter — no real email leaves the box).

The stock `priv/repo/seeds.exs` is empty; `mix ecto.setup` runs it as
part of database creation but seeds nothing.

## System Issues

### A world left running with `paused: false` for a long real-world gap can wedge the whole app on the next server start

`WorldServer.init/1` calls `catch_up/1` SYNCHRONOUSLY before `init/1`
returns — for a world with `paused: false`, this recomputes
`elapsed = now - turn_started_at` and replays that many missed turns
in a tight recursive loop (`run_missed/2`) before the process is
usable at all. If the dev machine (or a deployed box) sits idle for
days/weeks with a world still marked unpaused, the very first request
that touches that world after a restart (a page mount, a
`/dev/qa/worlds/:id/pause` call, anything routing through
`WorldServer.call/2` → `ensure_started/1`) blocks for as long as the
catch-up takes — observed 2026-08-21: turn count climbed from ~66k to
~90k over roughly 15 minutes and was still going. Confirmed impact
beyond that one world: while it was catching up, mounting
`BrokenOathsWeb.GameLive.Play` for a COMPLETELY DIFFERENT, already-paused
world produced an unhandled `** (EXIT) time out` crash page (5000ms
`GenServer.call` timeout inside `mount/3`), and a `join` click on that
other world hung silently for minutes with no crash and no error —
exact mechanism not fully isolated, but a full `kill $(lsof -ti :4050)`
+ restart, AFTER first setting `UPDATE worlds SET paused = true,
turn_started_at = now() WHERE id = <stuck world>` via `psql` (so the
new process's `catch_up/1` short-circuits instead of replaying), is
what unblocked everything. Filed as issue (see `create_issue` this
session) — before starting a QA session, it's worth a quick
`select id, turn, paused, turn_started_at from worlds;` to check
whether any `paused: false` world has a very stale `turn_started_at`,
and pausing it at the DB level BEFORE the first request touches it if so.

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

### MCP browser tools are unreliable — prefer the `vibium` CLI, verify against psql

The `mcp__*__browser_*` tools (as opposed to the `vibium` CLI) have shown
two distinct, reproducible failure modes, confirmed by multiple
independent QA sessions across 2026-08-21/22 (issue 5ab088cc, folding
in duplicate reports 124104ca and 6f8f3d1a):

1. **No per-agent isolation under concurrent QA.** All concurrent
   sessions share one cookie jar and effectively one browser
   tab/profile. Logging in as one account can surface a completely
   different concurrent agent's session mid-flow — including mid-way
   through that other session's own in-progress form submit (a
   password change was observed getting silently corrupted this way).
   Never run concurrent QA sessions that both rely on the MCP browser
   tools against the same dev server without serializing browser
   access between them.
2. **Unreliable "current page" tracking even solo.** Independent of
   concurrency, a `browser_navigate` + `browser_evaluate`/`get_text`
   pair can land on a blank or stale page with zero intervening calls;
   a `browser_wait` for an element `get_text` just showed can time out
   as "not found"; the very next call can show a fully logged-out
   session with no error surfaced anywhere in between.
   `browser_list_pages`/`browser_switch_page` can fail to find a page
   that was just navigated to and read from moments earlier. This
   reproduces in a single-agent, zero-contention session — retrying or
   serializing agents does not fully avoid it.

**What actually works** (story 938 QA, 2026-08-22): switch to the
`vibium` CLI (`vibium go`/`vibium find`/`vibium screenshot`, per the
Vibium section above) instead of the MCP `browser_*` tools, and
cross-verify every UI assertion against a `psql broken_oaths_dev` read
of the same data immediately after, rather than trusting a page read
alone. Both qa-938 and qa-939 report zero flakiness once they switched
to this combination for the rest of their sessions. For unit actions on
the canvas board specifically, pushing LiveView events directly via
`window.liveSocket.main.viewHooks[...].pushEvent(...)` (see
`board_click.sh`/`board_state.sh` above) is more reliable than
screen-coordinate click projection for units far from the default
camera angle.

**Update (2026-08-22, story 937 re-verification):** the CLI-over-MCP
mitigation above is necessary but not sufficient under HEAVY
concurrency (3+ agents driving vibium at once against the same dev
server). qa-936/qa-937/qa-940 all hit the same shared "current page"
pointer through the `vibium` CLI itself this round — sessions flipped
to other agents' logged-in accounts mid-sequence, and even
`vibium page new` + `vibium page switch <id>` immediately before an
action didn't give isolation, because the daemon's current-page
pointer is global regardless of which page id you just switched to.
The CLI+psql combination still works well for a SOLO agent or two
agents with light/infrequent browser use; for 3+ concurrent
browser-heavy QA sessions, **serialize exclusive browser access
between agents** (one agent drives the browser at a time; others do
non-browser prep/code-review in the meantime) rather than relying on
the CLI alone.

The underlying defect is in the vibium MCP server itself, not this
app's code — out of scope for a fix within this repo. Status: open,
mitigated (use the CLI + psql combination above).

### Sandbox blocks the vibium daemon socket

`vibium go`/`vibium daemon start` fail with "socket not available after
5s" under the default Claude Code sandbox — the daemon's socket lives
under `~/Library/Caches/vibium/`, which isn't in the sandbox's writable
path allowlist (only `~/.cache`, `~/.npm`, `~/.mix`, etc. are). Run
vibium commands with the sandbox disabled for this session (bash tool
`dangerouslyDisableSandbox: true`) rather than retrying in-sandbox.
Status: open (environmental, not an app bug).

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
