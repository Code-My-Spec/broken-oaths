# QA Result — Story 904 (Stone Age Progress Indicators)

## Status: PASS

## Scenarios

### Bronze Age progress at a glance (criterion 7639) — Stone Age countdown, live-updating

**PASS.** Logged in as `qa891a@test.local` (player 2, World 1, city 2, `size=4`,
`completed_techs={}`, no `current_research` selected — pure Stone Age per psql). Opened `/play`
— `[data-test="progress-panel"]` read `progress-age`="Stone Age", `progress-science-per-turn`="8"
(2 x city size 4, matches `Research.science_per_turn/1`'s own `2 * size` formula), `progress-
bronze-working`="0 / 100", `progress-turns-to-bronze`="13" (ceil(100/8), matches
`turns_to_bronze/3`).

`current_research` was `nil`, and `Research.accrue/2` is a documented no-op with nothing
selected, so science wasn't banking toward anything yet. Selected Bronze Working through the real
Tech panel (`tech-tree-button` -> `tech-bronze_working` -> confirmed the `bronze-working-warning`
modal -> `Game.set_research(world, user, :bronze_working)` fired). Paused the world
(`POST /dev/qa/worlds/1/pause`), then stepped 3 turns (`POST /dev/qa/worlds/1/step` x3) and
re-read the panel on a fresh `/play/1` mount:

| Point | `progress-bronze-working` | `progress-turns-to-bronze` | psql `banked_science.bronze_working` |
|---|---|---|---|
| Baseline (nothing selected) | 0 / 100 | 13 | 0 |
| Right after confirming research (1 turn ticked live) | 16 / 100 | 11 | 16 |
| After 3 more stepped turns | 40 / 100 | 8 | 40 |

Every DOM read matches the DB exactly. `progress-turns-to-bronze` visibly dropped 13 -> 11 -> 8 as
science accrued, live, through the real UI — not a static number. Resumed the world
(`POST /dev/qa/worlds/1/resume`) afterward.

Screenshots: `02_play_board_player2.png` (baseline), `03_research_selected_tech_panel.png`,
`04_before_step_paused.png` (16/100, 11 turns), `05_after_3_steps_countdown_dropped.png`
(40/100, 8 turns).

### Bronze Age progress at a glance (criterion 7639) — arrived state

**PASS.** Logged in as `qa@broken-oaths.test` (player 1, city 1, `size=6`, `completed_techs`
includes `bronze_working`, `banked_science.bronze_working=108` per psql). `/play/1` read
`progress-age`="Bronze Age", `progress-science-per-turn`="12" (2 x 6), `progress-turns-to-bronze`
="0" — correctly reflects "arrived," matching the component's own floor-at-0 logic
(`turns_to_bronze/3` floors `remaining` at 0 so a completed tech never shows a stale positive
countdown) and its own test suite (`progress_panel_test.exs`, "reads Bronze Age once
bronze_working is completed"). Screenshot: `06_player1_bronze_age_arrived.png`.

One display nit found here and filed (see Issues): `progress-bronze-working` reads "108 / 100"
rather than capping at cost — cosmetic only, doesn't affect age or the turns-to-Bronze figure
(both correct).

### Career totals so far (criterion 7640)

**PASS.** Player 1's psql ground truth (`game_cities` count=1, `game_players.camps_destroyed`=0,
`game_players.barbarians_killed`=1) matches the live DOM exactly: `progress-cities`="1",
`progress-camps`="0", `progress-barbarians`="1". Confirmed via `vibium html` read of the full
panel, not just a visual screenshot.

### Milestones mark on first achievement (criterion 7641)

**PASS.** Player 1 (1 city, 1 barbarian kill, 0 camps destroyed, 0 known players per psql
`game_known_players`): live DOM read confirmed `milestone-first-city` and `milestone-first-kill`
render `<span class="text-success font-semibold">Achieved</span>`, while
`milestone-first-camp` and `milestone-first-discovery` render
`<span class="opacity-50">Not yet</span>` — correct styling and text, independently flipped per
milestone, matching ground truth exactly. Player 2's baseline screenshot (before research
selection) additionally confirmed a second real account: `milestone-first-city`="Achieved" (has
1 city), the other three "Not yet" (0 kills/camps/discoveries) — consistent independent-flip
behavior across two different real players.

## Evidence

Screenshots in `.code_my_spec/qa/904/screenshots/`:
- `00_mailbox.png` — magic-link retrieval for player 2 login
- `01_play_landing_player2.png` — player 2 world picker
- `02_play_board_player2.png` — baseline progress panel, Stone Age, 8 sci/turn, 0/100, 13 turns
- `03_research_selected_tech_panel.png` — Tech panel after selecting Bronze Working
- `04_before_step_paused.png` — 16/100 banked, 11 turns (1 live tick after selecting research)
- `05_after_3_steps_countdown_dropped.png` — 40/100 banked, 8 turns (after 3 stepped turns)
- `06_player1_bronze_age_arrived.png` — player 1, Bronze Age arrived, full totals + milestones

psql evidence (inline in scenarios above): `game_player_research.banked_science`,
`game_players.camps_destroyed`/`barbarians_killed`, `game_cities.size`/count,
`game_known_players` — all read and cross-checked against the live DOM before, during, and after
the pause/step sequence.

## Issues

- **cae519c3-1a9e-4eeb-ad6e-72dbe3bdba35** (LOW, scope: app) — Progress panel's "Bronze Working"
  banked/cost display isn't capped at cost, so a player who has already arrived in the Bronze Age
  sees "108 / 100" instead of "100 / 100". Cosmetic only — age and turns-to-Bronze are both
  correct; only the raw banked-science figure overflows past the cost. Does not block PASS: the
  story's three acceptance criteria (glance-at-Bronze-Age-progress, career totals, milestones) are
  all functionally correct and live-verified.

## Session notes

- `mcp__vibium__browser_*` MCP tools were not present in this session's tool list; used the
  documented CLI fallback (`vibium` with `dangerouslyDisableSandbox: true`) per the QA plan and
  prior 903 session's precedent.
- `qa891a@test.local` has no password set (`hashed_password` null in psql) — used the real
  magic-link flow via `/dev/mailbox`, not the password form.
- World 1 was left unpaused (turn 9559) at session start; paused it before selecting research +
  stepping turns for player 2, resumed it (`POST /dev/qa/worlds/1/resume`) immediately after —
  confirmed `"paused":false` via a final `GET /dev/qa/worlds/1` at session end.
- Side effect: player 2 (`qa891a@test.local`) now has `current_research="bronze_working"` with
  40+ banked science (continuing to accrue live post-resume) instead of the prior
  "nothing selected" state. Still genuinely Stone Age (`completed_techs={}`) and still useful for
  future "still counting down to Bronze" QA — just no longer at the exact 0-banked starting point.
  Flagging for whichever future session next relies on this account's baseline.
- No `mix`/`iex`/`mix run` invoked this session — all DB reads via `psql broken_oaths_dev`, all
  state changes via the real browser UI or the dev-only `/dev/qa/worlds/:id/*` control surface.
