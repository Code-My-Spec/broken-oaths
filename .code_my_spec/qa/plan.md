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
(`/dev/dashboard`, `/dev/mailbox`). Probed status codes: public routes
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
`pkill -f "mix phx.server"` and restart. Status: open — recurred three
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
