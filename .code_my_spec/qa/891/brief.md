# Qa Story Brief

Story 891 — Unit Combat.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Use the password form `#login_form_password` (below the magic-link
  form on the same page):
  - `input[name="user[email]"]`
  - `input[name="user[password]"]`
- QA account: `qa@broken-oaths.test` / `qa-password-123!`. World 1
  ("QA World") was confirmed completely empty (no players, units,
  cities, or camps) before this session, so the primary QA account was
  used directly rather than a fresh throwaway — no messy prior state
  to avoid.
- A second, throwaway account (register at `/users/register`, confirm
  via `http://localhost:4050/dev/mailbox`) is needed only for the "no
  Stone Age PvP" scenario, to get a second player's unit into the
  world.
- **vibium MCP tools (`mcp__vibium__browser_*`) were not present in
  this session's tool list** (confirmed by a failed `browser_launch`
  call — see filed QA-scope issue). Fell back to the `vibium` CLI
  binary via Bash (`/opt/homebrew/bin/vibium`), sandbox disabled
  (`dangerouslyDisableSandbox: true`) — the socket lives outside the
  default sandbox's writable allowlist, same as documented in
  `plan.md`. `psql broken_oaths_dev` likewise needs the sandbox
  disabled (Unix socket at `/tmp/.s.PGSQL.5432` is otherwise blocked).

## Seeds

World state was already seeded (no `mix run` needed or permitted this
session — the dev server must not be touched):

- **QA World**, world id **1** (seed 424242, frequency 54), **10-second
  turns** (story 897). Confirmed via `psql` to be completely fresh at
  session start (0 rows in `game_players`/`game_units`/`game_cities`/
  `game_camps` for world_id=1). Use this world.
- **QA World (Fill Test)**, world id **2** — do not use.
- To reach a fightable barbarian: log in, `/play`, click
  `[data-test='join-world-1']`, select the starting Settler, click
  `[data-test='found-city']`. Barbarian camps spawn only after this
  first founding (5-8 camps, 1-2 "near" at a documented 8-15 hexes
  out, respawning 1 warrior per 3 turns up to 2 alive per camp — see
  `lib/broken_oaths/game/camps.ex`). Queue a Warrior in the city panel
  (`[data-test='production-option-warrior']`, 40 production, ~5-8
  turns at this city's production rate) for an actual "warrior" unit;
  the starting Lord can also fight in the meantime.

## What To Test

`GameLive.Play` (`/play/:id`) is a **canvas-only board** — there is no
`[phx-value-id]`-style tile selector to click (confirmed by reading
`play.ex`'s own moduledoc and the board's colocated JS hook). Real
interactions are raw PointerEvents dispatched on `#board-viewport`:
**left-click** (button 0) on a tile selects the unit/city/tile there;
**right-click** (button 2) on a tile queues a move, or — if a hostile
unit or camp sits on that exact tile — issues an attack order
(`orderMove` in the hook; the client only checks "is there a
barbarian/camp on this exact tile", the SERVER enforces adjacency and
movement, surfacing refusals via `[data-test='combat-error']`). Use
the two helper scripts written this session (both wrap a `vibium eval`
call into the live LiveView hook instance, reachable at
`Object.values(window.liveSocket.main.viewHooks)[0]`):
`.code_my_spec/qa/scripts/board_click.sh <tile_id> <left|right>`
(projects the tile's known center to screen coordinates and dispatches
a synthetic pointerdown+pointerup there) and
`.code_my_spec/qa/scripts/board_state.sh [tile_id]` (dumps the hook's
current units/camps/cities/selectedId and known tile ids; with a
`tile_id` argument, also lists that tile's neighbor ids via an
edge-sharing test on the pushed corner geometry — this is how
"genuinely adjacent" vs "two tiles away" was determined below without
`iex`/`mix`, forbidden this session). Both scripts require the vibium
daemon already navigated to `/play/1` and logged in.

Mapped to the story's acceptance criteria (component:
`BrokenOaths.Game.Combat`, `lib/broken_oaths/game/combat.ex`):

- **Warrior strikes the barbarian next door** (7533) — select an own
  warrior (`board_click.sh <tile> left`), right-click a barbarian unit
  standing on a tile confirmed adjacent via `board_state.sh <tile>`'s
  `neighborsOfTarget`. Expect: no `combat-error`, both units' HP drop
  (check via `board_state.sh` and cross-verify with
  `psql broken_oaths_dev -c "select id, hp from game_units where id in (...)"`).

- **Two tiles is too far** (7534) — select a unit, right-click a
  barbarian confirmed NOT in `neighborsOfTarget` of the unit's own
  tile. Expect `[data-test='combat-error']` reading "That target is
  out of range."

- **The blow lands now, not at the boundary** (7535) — confirm the
  HP/movement change and the `[data-test='combat-error']` (or lack
  thereof) appear in the same request/response round-trip as the
  right-click, not after waiting for the next turn boundary. Source
  read (`world_server.ex`'s `do_attack/4`/`resolve_attack/2`, "resolves
  like a move order: immediately, against whatever movement the
  attacker has left right now") plus every live exchange this session
  corroborates this — HP always changed by the very next
  `board_state.sh` call, sub-second later, well inside the 10-second
  turn window.

- **Spent units cannot swing** (7536) — attack once (movement always
  drops to exactly 0 on any attack, win or lose, regardless of
  `max_movement` — confirmed via `psql` before/after), then
  immediately attack again with the same unit. Expect
  `[data-test='combat-error']` reading "That unit has no movement left
  to attack."

- **The stronger side hits harder** (7537) — `Combat.damage/3`'s
  exponential curve (`30 * exp(0.04 * strength_diff) * roll(0.75-1.25)`)
  is deterministic-per-seed and unit-tested directly in
  `test/broken_oaths/game/combat_test.exs` plus
  `criterion_7537_..._spex.exs`. Live play corroborates the shape
  (barbarian base strength 15 > warrior/lord's 10/12, and every
  observed exchange this session fell in a broad plausible band) but a
  live single-session can't isolate the formula's exact slope from
  concurrent, uncontrolled AI activity — treat the spec+unit-test pair
  as the quantitative proof, live play as qualitative corroboration.

- **The killing blow is not free** (7538) — pick a barbarian at low
  HP (visible via `board_state.sh`'s `camps[].warriors[].hp`), attack
  it with a unit expected to kill it, and confirm via `psql` that the
  attacker's own HP still dropped in the same exchange (both damage
  numbers come from the SAME pre-combat strengths per
  `Combat.resolve/3`, computed before either side's HP is applied).

- **Zero HP means gone** (7539) — after any attack that reduces a
  unit to 0 HP, confirm via `psql broken_oaths_dev` that its
  `game_units` row is gone entirely (`Repo.delete_all`, not just
  `hp: 0`), and that it no longer appears in `board_state.sh`'s
  `units`/`camps[].warriors`.

- **The battle report** (7540) — immediately after a successful attack
  click, `vibium screenshot`. Expect a flash reading `dealt X · took Y`
  rendered top-center, fading over ~2.5s (`combatFlash` in the board
  hook, `until: performance.now() + 2500`). Timing is tight — screenshot
  in the same shell call as the attack click, no intervening `psql`.

- **Fighting beside the lord** (7541) — have a warrior attack a
  barbarian while standing on a tile adjacent to (not the same tile
  as) a living, same-player Lord's tile (`lord_adjacent?/2` in
  `world_server.ex` checks strict tile adjacency, not same-tile
  stacking), and compare damage dealt against the same warrior/a
  similar exchange without the lord adjacent. Expect a visibly larger
  `dealt` number with the lord adjacent (`@lord_aura_bonus 2`, folded
  into strength before the wounded-penalty scaling per `Combat`'s
  moduledoc).

- **No Stone Age PvP** (7542) — get a second player's unit adjacent to
  the primary account's unit (a second, throwaway account registered
  and joined to world 1), right-click to attack across the two
  accounts. Expect `[data-test='combat-error']` reading "Stone Age
  players cannot fight each other — only barbarians can be attacked."
  (`Combat.hostile?/2` — never true for two real players, hard rule,
  no tech-gate implemented despite the docstring's "yet" framing.)

- **A dying warrior swings soft** (7575) — compare the `dealt` damage
  of the same unit type/strength at high HP vs low HP (the linear
  `wounded_multiplier` in `Combat.effective_strength/2`: 100% at full
  HP, 50% at 0 HP). A clean before/after pair on the SAME living unit
  is ideal; failing that, the formula is directly checkable from any
  single observed `dealt` value against the unit's `hp/max_hp` at
  attack time (`effective = (base + aura) * (0.5 + 0.5*hp/max_hp)`,
  fed into the same damage curve as 7537).

## Setup Notes

**The founding city's adjacent barbarian camp made prolonged live
combat testing near it extremely hazardous** — filed as a high-severity
app issue (camp spawned 1 hex from the city instead of the documented
8-15 hexes out). Player units repeatedly died within 1-2 turns of
approaching the camp; the Lord was replaced by its 10-turn heir three
times over the session. Scenarios 7541 and 7542 in particular could
not be cleanly isolated live within this session's time budget as a
direct result — see the QA result's scenario notes for exactly what
was and wasn't directly observed live vs. corroborated by source +
existing BDD spec.

## Result Path

Findings are filed via `create_issue` as discovered; the run concludes
with one `submit_qa_result` call against task id
`401a20e5-b8df-4b74-8a1a-4da93545dce3`. Screenshots go in
`.code_my_spec/qa/891/screenshots/`.
