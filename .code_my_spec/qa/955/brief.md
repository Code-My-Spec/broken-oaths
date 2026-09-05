# Qa Story Brief

Story 955 — Library. Feature was implemented earlier by story 930; this
session's job is independent live-browser confirmation of the 8
acceptance criteria and cross-check against `BrokenOaths.Cities.Buildings`
and `BrokenOaths.Feudal.Bank`'s actual disband logic, alongside the
already-passing BDD specs at `test/spex/53_library/*.exs`.

## Tool

vibium CLI (per `.code_my_spec/qa/plan.md`'s "MCP browser tools are
unreliable" guidance — prefer `vibium go`/`find`/`eval`/`click` over the
`mcp__*__browser_*` tools), cross-verified against `psql broken_oaths_dev`
reads. `curl` for the dev-only `/dev/qa/worlds/:id` control surface
(step/pause/reload).

## Auth

    vibium go "http://localhost:4050/users/log-in"
    vibium fill "#login_form_password_email" "qa@broken-oaths.test"
    vibium fill "#user_password" "qa-password-123!"
    vibium click "#login_form_password button"

Credentials from `priv/repo/qa_seeds.exs` (qa@broken-oaths.test /
qa-password-123!).

## Seeds

No new seeds needed — reused the existing QA user's cities in two
already-seeded worlds:

- World 1 ("QA World", player_id 1) — used only for the "before Writing"
  negative check (criterion 2851), before this world was taken out of
  service mid-session by an unrelated incident (see Setup Notes).
- World 6 ("QA Copper Hunt 911", player_id 17, city_id 16) — used for
  the rest of the session. Writing (and its prerequisite Pottery) was
  granted via a direct `UPDATE game_player_research SET completed_techs
  = ...` (arrange step, not itself under test), followed by
  `POST /dev/qa/worlds/6/reload` to force the already-running
  `WorldServer` to pick up the change — safe only because world 6 was
  `paused: true` at the time (see Setup Notes for why this matters).

## What To Test

- **2851** (before Writing): on world 1/player 1 (Writing not yet
  researched), select city 1, confirm
  `[data-test='production-option-library']` is absent while
  `[data-test='production-option-warrior']` still renders normally.
- **2850/2854/2855** (after Writing): on world 6/player 17/city 16,
  after granting Writing, confirm
  `[data-test='production-option-library']` renders with text "Library
  90", `data-disabled="false"`, and no
  `[data-test='production-disabled-reason-library']` element.
- **Queue behavior**: click the Library option, confirm it enters the
  city's queue (appends behind any in-progress item rather than
  replacing it — city 16 had an in-progress Bronze Spearman at the
  time).
- **2852** (science +2): read `[data-test='science-per-turn']` (visible
  after `toggle_tech_panel`) before and after the Library completes via
  `POST /dev/qa/worlds/6/step` repeated until `banked >= cost` in
  `game_production_items`. Expect exactly +2.
- **2853/2856** (maintenance = 1, nets at turn boundary): read
  `[data-test='progress-gold-per-turn']` before/after completion.
- **2857** (shortfall protects the building): set the player's gold low
  (`UPDATE game_players SET gold = 5`, reload since world was paused),
  queue several Scouts (`[data-test='production-option-scout']`), step
  turns until upkeep exceeds income and the treasury is exhausted,
  confirm at least one unit disbands (`game_units` row count drops)
  while `game_cities.buildings` still contains `library` and
  `[data-test='city-building-library']` still renders.

## Result Path

Findings filed via `create_issue` as discovered; final result recorded
via `submit_qa_result` against task `55bab062-8559-48e3-9443-e918b4b1b4ac`.
No result.md — the DB attempt + linked issues are canonical.

## Setup Notes

**Incident during setup (see issue 78578bd1):** the first attempt used
world 1 (shared by ~12 QA players/stories). After granting Writing via
raw SQL, `POST /dev/qa/worlds/1/reload` was called to force the
already-running `WorldServer` to pick up the change — but world 1 was
`paused: false` at the time. Per `lib/broken_oaths/simulation/
world_server.ex:1892-1921`, `catch_up_step/1` only skips replay when
`state.world.paused` is true AT THE MOMENT `init/1` runs; for a live
world it recomputes `elapsed` from `turn_started_at` and replays in
chunks, and the chunked continuation never re-checks `paused` mid-flight
— so a subsequent `POST .../pause` call (which did return 200 OK) did
NOT stop the runaway replay already in motion. `turn` climbed from
~98734 to 115000+ over several minutes, and `/play/1` timed out on
mount for everyone in that world. This was filed as a critical issue
and the session switched to world 6 for the remainder of testing,
never touching world 1 again. **Lesson applied for the rest of this
session and worth carrying into future QA sessions: never call
`/dev/qa/worlds/:id/reload` on a `paused: false` world — pause first,
confirm `paused: true` via `GET /dev/qa/worlds/:id`, only then reload.**
Reloading an already-`paused: true` world (as done on world 6, twice)
was confirmed safe both by reading the source and by observing `turn`
stay flat across the reload.

The 2853/2856 delta observed live was -2 (not the BDD spec's isolated
-1), because a Bronze Spearman happened to complete in the same batch
of stepped turns as the Library. Cross-checked against
`BrokenOaths.Units.Maintenance`'s catalog (`bronze_spearman: 1`) —
the extra -1 is fully explained by the Spearman's own declared upkeep,
not a Library defect. Treated as corroborating rather than an isolated
repeat of criterion 2853, since the BDD spec already proves the fully
isolated -1 case.
