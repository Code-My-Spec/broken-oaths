# Qa Story Brief — 894 Camp Assault

Story 894 — Camp Assault. A military unit adjacent to a barbarian camp
can attack it; the camp (100 HP) never counters; damage is the
attacker's flat effective strength (10 warrior / 12 lord at full HP,
no random roll — unlike unit-vs-unit combat's ±25% curve); at 0 HP the
camp is destroyed, its destroyer's owner gets +30 gold, spawning
stops, the hex reverts to normal buildable terrain, and any warriors
the camp already spawned survive as live, legal, hostile targets.

## Tool

web (vibium CLI via Bash, sandbox disabled) plus `psql broken_oaths_dev`
for ground truth. **No `mix`/`iex` invocation of any kind this
session** — `plan.md`'s System Issues section (updated after this
session's prior 891-893 runs) now bans `mix run -e` outright, even for
"pure" reads, after an incident took the shared dev server down
mid-QA. This supersedes the task prompt's allowance of
`MIX_ENV=test mix run -e` for mesh math. `board_state.sh <tile_id>`'s
client-side corner-geometry adjacency check fully substitutes for the
BFS/neighbor math that would otherwise need mesh code — no server-side
computation is needed for this story's scenarios (all four criteria
only require single-hop adjacency to a camp, which the client already
knows for any tile in its fog window).

## Auth

Register a fresh account (needed to get a clean first-founding and its
guaranteed 1-2 immediately-visible "near" camps — reusing a
pre-founded QA player skips the founding moment and its camp reveal):

1. `vibium go "http://localhost:4050/users/register"`
2. Fill `user[email]` with `qa-894-a@broken-oaths.test`, submit.
3. `vibium go "http://localhost:4050/dev/mailbox"`, open the newest
   mail, then on the link page run `vibium eval "document.forms[0].submit()"`.
4. Stay logged in for the entire session on this one browser session —
   no need to exercise the password form separately; magic-link
   re-requests are unreliable this session per team-lead intel.
5. If the shared vibium daemon already has another QA session's user
   logged in, click `a[href='/users/log-out']` first and verify via
   `vibium eval "document.title"` / page text before proceeding.

## Seeds

No new seed script. World 1 ("QA World", id 1, freq 54, 10s turns) has
room — use it. World 2 ("QA World (Fill Test)") is full (both its 2
regions occupied by qa891pvpC/qa891pvpD) — do not attempt to join it.

Ground truth tables: `game_camps` (id, world_id, tile_id, hp,
spawn_counter, destroyed_at), `game_units` (camp_id links spawned
warriors to their camp), `game_players.gold`.

## What To Test

- Join world 1 (`[data-test='join-world-1']`), select the starting
  settler, `[data-test='found-city']`. `board_state.sh`'s `camps`
  array should immediately list 1-2 camps (the "near" camps, hp 100,
  no marching needed) — record the target camp's `id`/`tile_id`.
- Queue 2-3 warriors in the city panel
  (`[data-test='production-option-warrior']`), poll `board_state.sh`
  / psql `game_units` every ~15s until they appear (~6-8 turns each).
- **Free hits on the tents (7558):** Get a warrior onto a land tile
  adjacent to the camp — confirm adjacency via
  `board_state.sh <camp_tile_id>`'s `neighborsOfTarget`, march there
  with `board_click.sh <tile> right` waypoints one hop at a time,
  polling psql `game_units`/`game_camps` at every ~10s boundary (per
  team-lead intel: camp-spawned warriors will fight back, even though
  the camp itself never counters — march in pairs, expect losses,
  keep spares in the production queue). Once adjacent, right-click the
  camp's own tile with `board_click.sh <camp_tile_id> right` — the
  client hook infers a camp attack automatically
  (`orderMove`/`this.pushEvent("attack", {unit_id, target_camp_id})`
  in `play.ex`'s board hook) if a camp sits on that exact tile.
  Confirm via psql: camp `hp` drops, attacker's `hp` in `game_units`
  is unchanged.
- **Strength is the shovel (7559):** From psql, confirm each swing's
  damage against the camp is flat: a full-HP warrior removes exactly
  10 HP per swing (100 -> 90 -> 80 ...), a lord removes exactly 12,
  every time — no variance across repeated swings (unlike unit combat).
  A wounded warrior should hit for `floor(10 * (0.5 + 0.5 * hp/max_hp))`
  — if any attacker takes counter-damage from a camp-spawned warrior
  along the way, use that reduced-HP swing as a live wounded-damage
  data point.
- **The camp falls and the land opens (7560):** Continue attacking
  (movement recharges once per ~10s boundary, so roughly one swing per
  unit per turn) until the camp's psql `hp` hits 0. Confirm:
  `destroyed_at` gets set: the owning player's `game_players.gold`
  rises by exactly 30; the camp disappears from `board_state.sh`'s
  `camps` list; no further warriors spawn from that `camp_id` in psql
  across 3+ subsequent turns; the hex is walkable/buildable — move a
  unit onto the former camp tile and confirm a build/found action
  becomes available there (e.g. `[data-test='build-road']` after
  selecting a worker standing on it).
- **Orphans keep fighting (7561):** Confirm via psql that warriors
  already spawned from the destroyed `camp_id` (rows in `game_units`
  with that `camp_id`, inserted before `destroyed_at`) still have
  `hp > 0` and still exist as rows after the camp's destruction, and
  are still visible/attackable from the client (`board_state.sh`'s
  `units`/`camps[].warriors`, and a live re-attack against one of them
  via `board_click.sh` succeeds with nonzero damage).

## Result Path

No `result.md` — findings filed via `create_issue`, run recorded via
`submit_qa_result`. Screenshots under `.code_my_spec/qa/894/screenshots/`.

## Setup Notes

- MARCHING IS LETHAL near any camp's aggro range — camp-spawned
  warriors (up to 2/camp) will fight back even though the camp
  structure itself never counters. Move in pairs, poll psql at every
  boundary, keep spare warriors queued.
- `board_click.sh`/`board_state.sh` require the vibium daemon already
  navigated to `/play/<world_id>` and logged in, sandbox disabled.
- `psql broken_oaths_dev` needs the sandbox disabled too (Unix socket
  outside the default allowlist) — same as documented in `plan.md`.
