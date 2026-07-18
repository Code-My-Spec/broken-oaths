# Qa Story Brief — Story 904: Stone Age Progress Indicators

## Tool

web (Vibium — LiveView `ProgressPanel` on `/play`), corroborated with `psql broken_oaths_dev` for
ground truth and `curl` against the dev-only QA control surface (`/dev/qa/worlds/:id/*`) to drive
deterministic turns.

## Auth

Two seeded accounts on World 1 (id 1, "QA World"), both via the real password login form
(`#login_form_password` at `http://localhost:4050/users/log-in`):

- `qa@broken-oaths.test` / `qa-password-123!` — player 1. Per psql, `completed_techs` already
  includes `bronze_working` (Bronze Age arrived), `camps_destroyed=0`, `barbarians_killed=1`, one
  city (`size=6`). Use this account for the "arrived at Bronze Age" view and the career-totals /
  milestones view (first-city and first-kill achieved, first-camp and first-discovery not).
- `qa891a@test.local` / (magic-link only — no password set; use `/dev/mailbox` to read the login
  link) — player 2. Per psql, `completed_techs={}`, `current_research=nil`, one city (`size=4`,
  so `science_per_turn` = 8). Use this account for the "still counting down to Bronze" live view.
  Player 2 has no `current_research` selected, so science generated is not banked toward anything
  yet (`Research.accrue/2` is a no-op with `current_research: nil`) — select Bronze Working via
  the in-game Tech panel (`tech-tree-button` → `tech-bronze_working` → confirm the
  `bronze-working-warning` modal) before stepping turns, so banked science actually increases.

No API tokens in this app; everything authenticated rides the session cookie. Do not script cookie
jars — use Vibium (or the `vibium` CLI with `dangerouslyDisableSandbox: true` if the
`mcp__vibium__browser_*` MCP tools are not registered this session).

## Seeds

No new seeds needed — `qa@broken-oaths.test` and `qa891a@test.local` already exist on World 1
with the states described above (confirmed via psql, not re-seeded here). Do not run `mix run` —
another agent owns the mix build this session; use psql only for DB reads.

## What To Test

- **Bronze Age progress at a glance (criterion 7639).** As player 2 (`qa891a@test.local`, Stone
  Age, `science_per_turn=8`, nothing banked toward Bronze Working yet): open `/play`, confirm the
  `[data-test="progress-panel"]` shows `progress-age` = "Stone Age",
  `progress-science-per-turn` = "8", `progress-bronze-working` = "0 / 100", and
  `progress-turns-to-bronze` = "13" (ceil(100/8)). Then select Bronze Working as current research
  via the Tech panel (confirm the warning modal), pause the world
  (`POST /dev/qa/worlds/1/pause`), step 1-2 turns (`POST /dev/qa/worlds/1/step`), and re-read the
  panel — `progress-bronze-working` and `progress-turns-to-bronze` must have moved (banked up,
  turns down), corroborated against `game_player_research.banked_science` in psql.
- **Bronze Age "arrived" view.** As player 1 (`qa@broken-oaths.test`, already `bronze_working`
  completed): open `/play`, confirm `progress-age` = "Bronze Age" and
  `progress-turns-to-bronze` reads a sensible "no turns remaining" value (per the component's own
  test suite this renders "0", not a hidden row — confirm this is what's live, not a stale/wrong
  number).
- **Career totals (criterion 7640).** As player 1: confirm `progress-cities` = "1",
  `progress-camps` = "0", `progress-barbarians` = "1" — matches psql
  (`game_cities` count, `game_players.camps_destroyed`, `game_players.barbarians_killed`).
- **Milestones (criterion 7641).** As player 1: confirm `milestone-first-city` and
  `milestone-first-kill` read "Achieved" (green/success styling) and `milestone-first-camp` /
  `milestone-first-discovery` read "Not yet" — matches the 1 city / 0 camps / 1 kill / 0
  known-players ground truth in psql. As player 2 (no cities/kills/camps/discoveries yet, before
  the research-selection step above changes only research state): confirm all four milestones
  read "Not yet".
- **Live-updating check.** Screenshot the progress panel before and after the pause+step turn
  advance for player 2 to demonstrate `progress-turns-to-bronze` visibly drops as science accrues,
  not just a psql-only claim.

Resume the world (`POST /dev/qa/worlds/1/resume`) once done so it doesn't stay frozen for other
sessions.

## Result Path

Findings are filed live via `create_issue` (per the task prompt) and the session concludes with
`mcp__plugin_codemyspec_local__submit_qa_result`. Supporting screenshots go to
`.code_my_spec/qa/904/screenshots/`.

## Setup Notes

Dev server is already running on `http://localhost:4050` — do not restart it, do not run
`mix`/`iex`/`mix run` this session (a separate agent owns the mix build; a concurrent compile can
kill or wedge the dev server per the QA plan's "System Issues" section). Use
`psql broken_oaths_dev` for all DB ground-truth reads. The dev QA control surface
(`/dev/qa/worlds/1/*`) is documented in `.code_my_spec/qa/plan.md` under "Deterministic
Multiplayer QA" — pause before making any state changes, step turns on demand, resume when done.
