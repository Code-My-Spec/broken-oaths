# Qa Story Brief

Story 893 — Barbarian Behavior. Barbarians hunt, attack, and pillage on
their own: 1-hex-per-boundary movement toward the nearest player unit
or undefended city within 5 hexes (never chasing beyond 5 hexes of
their own camp — the leash), attack-on-sight with no diplomacy option,
never attack each other, pillage a completed improvement on entry, and
pay a 10-gold bounty when killed.

## Tool

web (LiveView via the vibium CLI) for all player-facing actions, plus
`psql broken_oaths_dev` for ground truth on barbarian/unit/gold state,
plus `MIX_ENV=test mix run <script>` for pure hex-mesh math only (BFS
land-path distance and adjacency — never game state).

## Auth

Register a fresh account via `/users/register`, confirm via the magic
link in `http://localhost:4050/dev/mailbox` (the confirmation page
needs no `document.forms[0].submit()` — following the link alone
already lands you logged in for this account's confirmation flow, no
form submit was required in practice). If the shared vibium browser
session already has someone else logged in, click
`a[href='/users/log-out']` first — the daemon is shared across QA
sessions and cookies persist.

## Seeds

No seed script needed beyond what's already in the dev database.
World 1 ("QA World", id 1, freq 54, 10s turns) has room to join — use
it. World 2 ("QA World (Fill Test)", id 2, freq 8) is **full** as of
this session (both its 2 spawnable regions are occupied) — the `/play`
picker shows it disabled.

Both worlds already carry a large population of real, independently
roaming barbarian camps and units from prior QA sessions (world 1: 21
camps / ~42 warriors; world 2: 6 camps / 12 warriors) — a "living lab"
useful for passive observation, but as of this session **no existing
camp's leash reached any existing player's units/cities** (closest gap
found was 6 hexes, 1 over the 5-hex leash). Live hunt/attack scenarios
need a **fresh account** so a newly founded city reveals a camp near
your own starting position instead.

## What To Test

- **The hunt closes in / no parley (criteria 7551, 7553):** Register,
  join world 1, found your city with the starting settler
  (`[data-test='found-city']` after left-clicking the settler's tile).
  Note the revealed camp's tile via `board_state.sh`'s `camps` array.
  Compute true BFS land-path distance from camp to your lord via the
  mesh-math script (raw tile-id gaps are not reliable distance
  proxies on this mesh) — a camp 10 hexes out (this session's camp 35)
  will NOT hunt regardless of how the map looks; march your lord
  toward it with `board_click.sh <tile> right` waypoints (queue_move is
  a single-waypoint order, consumed on arrival — re-click a new
  waypoint each time fog reveals further tiles) until within ~4 hexes.
  Poll `psql` every ~11s for your lord's `tile_id`/`hp` and the camp's
  warriors' `tile_id`/`hp` — a warrior within leash+aggro range will
  visibly close 1 hex per boundary, then attack once adjacent with HP
  loss on your side, all without you ever sending an `attack` event.
  **Warning: this reliably kills an unescorted unit in this world** —
  confirmed twice this session (a lord and a follow-up warrior both
  died). The game auto-respawns a fresh lord garrisoned on your own
  city after your lord dies, so the account survives.

- **Out of sight, out of mind (criterion 7552):** No staging needed —
  pick any camp whose warriors are NOT currently near a player (most
  of the existing living-lab camps qualify; verify via the mesh-math
  script that camp-tile-to-every-player-tile distance exceeds 5) and
  poll its warriors' `tile_id` over several boundaries. Distance from
  camp tile should never exceed 2 (the `@roam_radius`).

- **They smell the undefended city (criterion 7554):** Hard to stage
  live without a test-only fixture (the BDD spex itself needed
  `Fixtures.isolate_camp/2` and instant relocation to make this safe
  and deterministic — see the spex file's own moduledoc). Verify via
  `lib/broken_oaths/game/barbarian_ai.ex`'s `nearest_target/5` (an
  undefended city always outranks any unit, regardless of relative
  distance) and confirm `mix test test/broken_oaths/game/barbarian_ai_test.exs`
  passes — it has direct tests for both "prefers an undefended city
  over a closer player unit" and "a defended city ... is not
  preferred."

- **Honor among savages (criterion 7555):** No staging needed — any
  camp with 2 alive warriors works, including a freshly spawned pair.
  Poll both warriors' `tile_id`/`hp` over several boundaries; HP should
  never change relative to each other even while standing adjacent.

- **The farm burns but the field remains (criterion 7556):** Genuinely
  hazardous to stage live in this world without a test fixture — the
  only camp within reach of a fresh account killed both units sent
  into its aggro range this session, and a worker needs 3 exposed
  turns standing still to build. If attempting: produce a worker,
  build the farm (`select_unit` then `[data-test='build-farm']`) on a
  camp-adjacent tile using `Fixtures`-style bridge-tile reasoning
  documented in the spex file, then lure a target through it. Verify
  via source (`Improvement.pillage/1`) if live staging is skipped —
  note there is currently **no unit test** for `pillage/1` itself
  (issue filed), so source review is the only fallback verification
  available right now besides the spex file.

- **The bounty (criterion 7557):** Much more tractable than it looks —
  a barbarian that hunted a player unit out past its own roam radius
  and then loses its target (target dies/leaves) can get **stranded**
  motionless outside roam range (issue filed) until a new target
  arrives. Production-queue a warrior (`queue_production` item
  `warrior`, city panel via `pushEvent('select_city', {city_id})`),
  march it to the stranded/wounded barbarian's tile, and let the
  automatic boundary-attack resolve — check `game_players.gold` before
  and after via psql; it should rise by exactly 10 once the barbarian
  dies, even if your own unit also dies in the same exchange.

## Result Path

No `result.md` — findings are filed via `create_issue` (scope `app`
except QA-tooling problems, which are `qa`) and the run is recorded via
`submit_qa_result`. Evidence/log artifacts for this session are under
`.code_my_spec/qa/893/` (this brief; the mesh-math script used lives in
the session scratchpad, not checked in).

## Setup Notes

- `mix spex <files> --verbose --trace` did not produce usable output
  this session (no compiler/ExUnit trace, just a terse "clean /
  analysis run N / failures: 0" that never varied with the actual
  files passed) — issue filed. Use plain `mix test <path>` for
  anything under `test/broken_oaths/` (that works normally); for
  `test/spex/**/*_spex.exs` files specifically, `mix spex` is the only
  runner (default `mix test` pattern doesn't match `_spex.exs`) but
  could not be independently verified as functioning this session.
- `create_issue` with `scope: framework` 401s ("Invalid deploy key") —
  that scope routes to a hosted server this local session isn't
  authenticated against. Use `scope: qa` for QA-tooling problems
  instead; it stays local and works.
- Raw tile-id numeric gaps are **not** a usable distance proxy on this
  hex mesh (e.g. two tiles ~7000 apart numerically were 1 hex apart
  geometrically). Always compute via the mesh math script.
