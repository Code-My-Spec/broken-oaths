# Qa Story Brief — 892 Barbarian Camps Spawn

## Tool

web (vibium CLI) primary; psql for ground truth; `MIX_ENV=test mix run -e` for pure mesh/region math only.

## Auth

- Dev server already running at http://localhost:4050 — never restart it, never run plain `mix`/`iex`.
- Fresh accounts (needed for spawn-trigger scenarios — reusing a world's pre-founded player doesn't exercise "first founding"):
  1. `vibium go "http://localhost:4050/users/register"`, fill `user[email]` with a unique address (e.g. `qa-892-a@broken-oaths.test`), submit.
  2. `vibium go "http://localhost:4050/dev/mailbox"`, open the newest confirmation email, then on the magic-link page run `vibium eval "document.forms[0].submit()"` (button clicks are flaky here — known issue).
  3. Land authenticated on `/play`; join world via `[data-test='join-world-<id>']`.
- Existing seeded QA users (world 1/2) already have founded cities + 6 camps + roaming barbarians each — usable as ground truth corroboration (psql) for the cadence/cap criteria without spending real time waiting, but NOT for the first/second-founding trigger criteria (those need genuinely fresh players).

## Seeds

No new seed script needed. Both worlds are pre-seeded:
- World id 1, "QA World" (seed 424242, freq 54, 29,162 tiles, 10s turns).
- World id 2, "QA World (Fill Test)" (seed 111222, freq 8, 642 tiles, 10s turns) — **prefer this world for fresh-account scenarios**, much faster to work in.

Ground truth tables: `game_camps` (id, world_id, tile_id, hp, spawn_counter, destroyed_at), `game_units` (type='barbarian_warrior', camp_id, hp, tile_id), `game_cities`, `worlds.turn`. No `attack`/`defense` columns exist on `game_units` — those are computed live (`Combat.base_strength/1` = 15 for barbarian_warrior) and only observable via the `game:camps` push (`board_state.sh` → `h.camps[].warriors[].attack/defense`).

## What To Test

- **7543 — first founding spawns 5-8 camps (1-2 near, 4-6 far), 8-15 hexes, never adjacent.** Register fresh account A, join World 2, note world's camp count via psql. Select own settler (left-click on canvas) → `[data-test="found-city"]` button in the unit panel. Immediately after, `board_state.sh` should list 1-2 already-visible camps (hp 100) — these are the "near" camps (no fog roll needed). Diff psql `game_camps` before/after: expect world count +5..+8 total. For every newly inserted camp tile_id, compute region membership + BFS ring distance from the city tile via a single `MIX_ENV=test mix run -e` call using `%BrokenOaths.Worlds.World{seed: .., frequency: ..}`, `BrokenOaths.Worlds.Regions.partition/1` (home region set) and `Regions.adjacent_tiles/2` (BFS rings) — same technique the BDD spec (criterion 7543) uses. Expect: near camps in the home region, far camps outside it; both bands 8-15 hexes out (small regions may legitimately fall back to 4+ hexes per the module doc — never adjacent, i.e. ring distance 1).
- **7544 — later foundings spawn nothing; another player's first founding does.** Same account A: grow city to size 2 (advance turns via real time — 10s/turn), queue a settler, march it 4+ hexes (`board_click.sh <tile> right` after selecting the settler), found a second city. psql world camp count must be unchanged from the post-first-founding count. Then register fresh account B, join the same world, found ITS first city — psql world camp count must increase again (+5..+8), proving the trigger is per-player-first-founding, not per-world-first-founding.
- **7545 — camp discovered is camp marked.** Pick a "far" camp tile_id from psql ground truth (not in the initial `board_state.sh` camps list). March the lord toward an adjacent land tile via repeated `board_click.sh <tile> right` + waiting for turns to advance (10s each). Poll `board_state.sh` each turn; assert the target tile_id is absent before arrival and present (with matching id/hp) once the lord is within sight.
- **7546 — fog keeps its secrets.** While marching in 7545 (and independently, right after founding in 7543), repeatedly poll `board_state.sh` camps across several turns and diff against the FULL psql camp/warrior list. Assert no not-yet-explored camp id, tile_id, or warrior id ever appears in `h.camps`, even as psql shows those hidden camps' `spawn_counter` climbing and warriors accumulating underneath.
- **7547 — breeds on a cadence (1 warrior / 3 turns / camp).** Use one of account A's own immediately-visible near camps (observable from turn 0, no marching). Poll `board_state.sh` every ~10s (one turn); note the turn (via psql `worlds.turn`) at which `warriors` count first increases from its starting value. Expect exactly +3 turns from the last observed count change.
- **7548 — cap holds (max 2 alive/camp).** Two evidence sources: (a) psql on the pre-existing worlds — turn 489 (world 1) / 339 (world 2), camps founded ~200-260 turns ago, already show exactly 2 `barbarian_warrior` rows per `camp_id` for all 12 camps — strong long-run evidence the cap holds. (b) Live: continue polling the 7547 camp past its first two spawns (~6+ turns / 5-6 cadence cycles, several minutes of 10s turns) and confirm `warriors` never exceeds 2 in any poll.
- **7549 — born mean (15/15/120).** Once a warrior appears on the 7547 camp, read its `attack`/`defense`/`hp` straight from `board_state.sh`'s `h.camps[].warriors[]` (the real push payload) — expect 15/15/120. Cross-check `hp` against `psql game_units` for that unit id.
- **7550 — the attention warning.** Screenshot immediately after account A's FIRST founding (7543) — expect flash banner text "Your city attracts attention. Barbarian camps are forming in the wilderness." (`vibium eval` page text or `browser_get_text`). Screenshot again right after the SECOND founding (7544) — the flash must NOT repeat (assert absent).

## Setup Notes

- Never run plain `mix`/`iex` against the dev build — only `MIX_ENV=test mix run -e '...'` for pure `BrokenOaths.Worlds.{World,Regions}` math (no Repo/GenServer calls; isolated `_build/test`, cannot touch the running dev server's `_build/dev`). Verify server health (`curl .../health`) before/after each such call as a tripwire.
- Left-click selects (shows unit/city side panel with action buttons), right-click on the canvas via `board_click.sh` queues a move or attack. `board_state.sh [tile_id]` dumps the client's fog-filtered `units`/`camps`/`cities`/known-tile-ids, and neighbor tiles when given an argument.
- `/play/:id` has no sidebar toggle (that only exists on the world list page, `world_live/show.ex`) — ignore any stale plan.md reference to `toggle_sidebar` here.
- The barbarian warning is a standard `put_flash(:info, ...)` rendered through `<Layouts.flash_group>` — visible directly in a screenshot or page text, no special handling needed.
- Do not seed or activate any frequency 5-6 world (Spawner crash, issue 6b8a69f3).

## Result Path

.code_my_spec/qa/892/ (screenshots under `screenshots/`). Findings filed live via `create_issue`; final record via `submit_qa_result` — no result.md.
