# Qa Story Brief

Story 903 — Advancing to Bronze Age.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Password form `#login_form_password`:
  - `input[name="user[email]"]`
  - `input[name="user[password]"]`
  - Submit button inside `#login_form_password`
- Primary account: `qa@broken-oaths.test` / `qa-password-123!` — player 1
  on World 1 (id 1), city 1 ("City 1", tile 14725, currently size 6 —
  see Setup Notes for why this city is NOT used as growth-cap
  evidence), with Mining/Pottery/Animal Husbandry already completed
  (from 902 QA). Only Bronze Working is left to research — cheapest
  path to the Bronze Age flip.
- Secondary throwaway account (for a clean, live "grows past the
  Stone Age cap of 4, all the way to 6" trace): register a new account
  at `http://localhost:4050/users/register` (magic-link flow — no
  password needed to register), email `qa903-growth@broken-oaths.test`,
  read the confirmation link from `http://localhost:4050/dev/mailbox`
  (Swoosh local adapter). Join **World 1** (id 1) from `/play`.
- Read-only corroboration account (no login needed — psql only):
  player 2 (`qa891a@test.local`) on World 1, city 2, already size 4
  with food massively past any threshold and zero completed techs —
  live evidence the Stone Age cap holds independent of anything this
  session does.
- Driven with `mcp__vibium__browser_*` tools (or the `vibium` CLI with
  sandbox disabled if MCP tools aren't present).
- **Tech panel and city panel are real DOM** (not canvas) — click
  `[data-test='tech-tree-button']`, `[data-test='tech-bronze_working']`,
  `[data-test='bronze-working-confirm']`,
  `[data-test='production-option-*']` etc. directly.
- **The board itself is canvas-only** — no tile DOM for unit/city
  selection or move/attack orders. Use the `liveSocket` hook-eval
  workaround (established in stories 878-901's QA):

      window.liveSocket.owner(document.getElementById('board-viewport'), view => {
        const hook = view.viewHooks[Object.keys(view.viewHooks)[0]];
        hook.pushEvent('select_city', {city_id: 1});
        // or: hook.pushEvent('select_unit', {unit_id: <id>});
        // or: hook.pushEvent('attack', {unit_id: <id>, target_unit_id: <id>});
        // or: hook.pushEvent('queue_production', {city_id: <id>, item: 'bronze_spearman'});
      });

  This dispatches through the exact same `Play.handle_event/3` code
  path as a real click/tap. `.code_my_spec/qa/scripts/board_click.sh`
  is also available for real synthetic pointer clicks on a known
  tile_id if preferred (needs a tile_id currently in the client's
  fog-filtered window — see `board_state.sh`).

## Seeds

    mix run priv/repo/qa_seeds.exs   # already current — do NOT re-run

No new seed script needed. State re-verified via `psql broken_oaths_dev`
(sandbox disabled) immediately before writing this brief:

- **World 1** (id 1, frequency 54, turn ~9277 at brief time, paused by
  this session via `POST /dev/qa/worlds/1/pause` — resume when done).
- Player 1 (`qa@broken-oaths.test`): `game_player_research` row shows
  `completed_techs = {mining, pottery, animal_husbandry}`,
  `current_research = nil`. City 1 is size 6 already (food 91270+) —
  **this predates this QA session and predates the research feature's
  own rollout; do not treat city 1 as clean growth-cap evidence for
  criteria 7635/7636**, it's only useful for the age-flip / Bronze
  Spearman / profile-reflects-age criteria (7632, 7633, 7638), where
  city size is irrelevant. Player 1 currently has NO lord unit (only a
  `worker`, id 378) — lord is presumably dead from an earlier session;
  not a blocker, combat doesn't require it.
- Every OTHER city in World 1 (players 2, 5, 6, 7, 8 — ids 2, 4, 5, 6,
  7) is already sitting at size 4 with food far past any threshold and
  an empty `completed_techs` array — this is itself live, read-only
  corroboration that the Stone Age cap holds (5-for-5), independent of
  city 1's anomaly.
- Use `curl http://localhost:4050/dev/qa/worlds/1` to confirm
  `"paused": true` before making any changes; `POST .../step` to
  advance turns on demand (instant, no wall-clock wait — use a bash
  loop for many steps).

## What To Test

### 7632 — Bronze Working flips the age (player 1)

1. Log in as `qa@broken-oaths.test`, navigate to `/play/1`.
2. Click `[data-test='tech-tree-button']`, then
   `[data-test='tech-bronze_working']`. Confirm
   `[data-test='bronze-working-warning']` modal appears with copy
   "This will advance you to Bronze Age. Continue?". Screenshot.
3. Click `[data-test='bronze-working-confirm']`.
4. `POST /dev/qa/worlds/1/step` repeatedly (bash loop; city 1 is size
   6 ⇒ 12 science/turn per `Research.science_per_turn/1`, so ~9 steps
   banks the 100-cost Bronze Working). Poll
   `psql -c "select completed_techs, current_research, banked_science from game_player_research where world_id=1 and player_id=1;"`
   between steps.
5. The instant `bronze_working` lands in `completed_techs`, confirm
   (reload/observe the live view) a `game:age` toast fires with exact
   text "You have entered the Bronze Age! New units and buildings
   unlocked." (toast renders in `#game-toasts` as
   `[data-test='game-toast']`). Screenshot.
6. Confirm `[data-test='age-panel']` / `[data-test='age-status']`
   reads "Bronze Age" (was "Stone Age" before). Screenshot both
   before/after states.

### 7633 — the Spearman outfights a barbarian (player 1, after 7632)

1. Select city 1 via the `pushEvent('select_city', {city_id: 1})`
   workaround. Confirm `[data-test='city-panel']` is open.
2. **First, test the REAL UI path**: look for
   `[data-test='production-option-bronze_spearman']` in the Build
   list. Record whether it renders. (See Setup Notes — source reading
   of `GameLive.CityPanel`'s `@catalog` module attribute suggests it
   may NOT, since that list is hardcoded to
   `[:settler, :worker, :warrior]` and was never extended for 903's
   `bronze_spearman` — confirm this live, don't assume the source
   reading is stale.)
3. If the button is absent, fall back to
   `hook.pushEvent('queue_production', {city_id: 1, item: 'bronze_spearman'})`
   (same event Play's real handler processes) so the rest of this
   scenario can still be exercised — note in the observation that this
   required the fallback.
4. `POST .../step` repeatedly until `game_production_items` shows a
   completed bronze_spearman and `game_units` gains a
   `type = 'bronze_spearman', player_id = 1` row (psql poll). Confirm
   its stats: `hp = 120`.
5. Find an adjacent land tile to the spearman not occupied by the
   player, spawn a barbarian there:
   `POST /dev/qa/worlds/1/barbarians -d tile_id=<adjacent tile>`.
6. Select the spearman (`select_unit`), then repeatedly
   `hook.pushEvent('attack', {unit_id: <spearman_id>, target_unit_id: <barbarian_id>})`,
   recharging movement between strikes as needed
   (`PATCH /dev/qa/worlds/1/units/<spearman_id> -d recharge=true`,
   or `POST .../step` once per exchange) until the barbarian's hp
   reaches 0 (confirm via psql — barbarian unit disappears/hp=0) or 10
   exchanges pass.
7. Confirm the spearman survives with hp > 0 (psql). Screenshot the
   unit panel showing the spearman's hp mid/post-fight.

### 7635 — cities grow past the Stone Age cap, to size 6 (fresh account)

1. Register/join as described in Auth. Found the starting settler's
   city (real `[data-test='found-city']` button after `select_unit` on
   the settler via the board workaround; if it's still dead per the
   known bug from stories 878/879/880 — issue `ee6f7ccb` — fall back to
   the `liveSocket` `found_city` push; note which path worked).
2. Immediately snapshot the new city's id/tile/size/food via psql.
3. Open the tech panel, select+confirm Bronze Working right away (runs
   in parallel with food-driven growth).
4. `POST .../step` in a loop (bash `for`, no per-call wait needed —
   try 30-40 first), polling `game_cities` for this city's `size`.
   Confirm it reaches **size 4 and stalls there** for at least a few
   more steps while `completed_techs` still lacks `bronze_working`
   (corroborates 7636 live, on a CLEAN city unlike city 1).
5. Keep stepping until `bronze_working` lands in
   `game_player_research.completed_techs` for this player (should take
   on the order of 50-80 turns total from founding, per
   `SharedGivens.player_reached_bronze_age`'s own math — a size-1..4
   city banks ~2-8 science/turn).
6. Continue stepping post-flip. Confirm `size` climbs 4 → 5 → 6 (one
   growth per tick, per `Yields.grow/4`'s "at most once per city per
   tick" — expect a few more steps once food is already banked past
   threshold). Stop the instant `size == 6`.
7. Confirm via the UI: reload `/play/1`, select this city, screenshot
   `[data-test='city-size']` = "6".

### 7636 — a Stone Age city still caps at 4 (read-only corroboration + live)

1. The fresh account's own city from 7635, BEFORE its Bronze Working
   flip (step 4 above) is itself live evidence: size stalls at 4 with
   `completed_techs` still empty of `bronze_working`.
2. Additionally, read-only via psql (no login/mutation needed): pick
   any of players 2/5/6/7/8 on World 1 (all size-4, all zero completed
   techs, all with food far past any Stone Age threshold already).
   Snapshot `food` now, `POST .../step` a few times, snapshot `food`
   again. Confirm `size` unchanged (4) and `food` increased — banking
   continues, growth stays frozen. Record which player/city id and the
   before/after food numbers.

### 7637 — barbarians don't scale up with the player (spot-check via psql)

1. After player 1 has reached the Bronze Age (7632), confirm via
   source + a fresh barbarian spawn that barbarian stats are
   unaffected: `POST /dev/qa/worlds/1/barbarians -d tile_id=<any land
   tile>` and immediately `psql -c "select type, hp, max_hp from
   game_units where id = <returned id>;"` — expect `hp = max_hp = 120`
   (`Combat.base_strength(:barbarian_warrior)` is a hardcoded module
   attribute of 15, never read from any player's research state — cite
   this in the observation alongside the live spawn).
2. This is a spot-check per the task instructions — no live combat
   re-run required beyond what 7633 already exercises (that fight's
   damage-taken numbers are themselves evidence the barbarian was
   still Stone-Age-strength while player 1 was already Bronze Age).

### 7638 — profile reflects the age (player 1, persistence check)

1. After 7632's flip, fully reload `/play/1` (a brand-new LiveView
   mount, not just the same open tab) — either close/reopen the
   browser tab or use `mcp__vibium__browser_navigate` to the same URL
   again.
2. Confirm `[data-test='age-panel']` / `[data-test='age-status']`
   still reads "Bronze Age" on this fresh connection (proves the age
   is read from durable `completed_techs`, not a stale socket assign
   from the moment of completion). Screenshot.

## Result Path

No `result.md` file — findings are filed via `create_issue` as
discovered and the session concludes with one `submit_qa_result` call
against task id `1f6d4f54-ff8f-45b9-9245-547030475caf`. Screenshots go
in `.code_my_spec/qa/903/screenshots/`, raw psql/curl evidence
transcripts in `.code_my_spec/qa/903/responses/`.

## Setup Notes

- Dev server is already running at `http://localhost:4050` — do not
  restart it, do not run `mix phx.server`/`mix compile`/`mix format`/
  `mix test`/`mix spex`/`mix run`/`iex -S mix`. `psql broken_oaths_dev`
  is the only sanctioned ground-truth read tool alongside the browser;
  both require the sandbox disabled (`dangerouslyDisableSandbox: true`).
- **Likely real bug, confirm live before filing**:
  `lib/broken_oaths_web/live/game_live/city_panel.ex` line ~41 defines
  `@catalog [:settler, :worker, :warrior]` as a hardcoded, compile-time
  module attribute — never extended for `:bronze_spearman` (story 903)
  or `:granary` (story 902). If confirmed live (no
  `production-option-bronze_spearman` button ever renders, Bronze Age
  or not), this is a HIGH severity app bug: the story's own acceptance
  criterion "Bronze Spearman becomes buildable... open a city's
  production, confirm Bronze Spearman is offered" fails through the
  real UI even though the underlying `Game.queue_production/4` +
  `Production.can_queue?/3` gating works correctly when driven directly
  (which is how the BDD spex for criterion 7633 exercises it, via
  `render_hook` bypassing the catalog list entirely — the spex passing
  does NOT prove the UI offers the option).
- World 1 is shared with several other throwaway QA players from prior
  stories (879-901) — pausing/stepping affects the whole world equally;
  that's expected and matches every prior session's own recipe. Resume
  the world (`POST /dev/qa/worlds/1/resume`) once done, unless leaving
  it paused is explicitly useful for a follow-up session (note either
  way in the final report).
- Time-box aggressively. 7635's growth-from-1-to-6 trace is the biggest
  step-count sink but each `/step` is instant (no wall-clock wait) —
  script it as a bash loop rather than calling `/step` one curl at a
  time interactively.
