# Qa Story Brief

Story 877 — Region Placement with Room to Expand.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Use the password form `#login_form_password` (not the magic-link form above it):
  - `input[name="user[email]"]`
  - `input[name="user[password]"]`
- Primary QA account: `qa@broken-oaths.test` / `qa-password-123!`
- Throwaway accounts for multi-user scenarios: register at
  `http://localhost:4050/users/register` with any `name@example.test`
  email, then read the confirmation/magic-link email from
  `http://localhost:4050/dev/mailbox` (Swoosh local adapter).
- Driven with the `vibium` CLI (bash), not the vibium MCP tools (not
  present in this session): `vibium go <url>`, `vibium find <selector>`,
  `vibium click <selector>`, `vibium fill <selector> <text>`,
  `vibium screenshot` (path arg is broken — always writes
  `~/Pictures/Vibium/screenshot.png`; copy aside per scenario). Run
  vibium with the sandbox disabled (socket lives outside the sandbox
  writable allowlist). If vibium wedges: `pkill -f chrome-for-testing;
  pkill -x vibium; rm -f ~/Library/Caches/vibium/vibium.sock`, then
  `vibium go` again (always re-navigate after a restart).
- `iex -S mix` for state inspection only ("find, not prove" per the QA
  plan) — used here narrowly to read `Player.region_id` and
  `Regions.partition/1` sizes, since the UI has (deliberately) no
  region-id or region-boundary display to assert against directly.

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent; confirmed both fixtures present this run:

- QA user `qa@broken-oaths.test` / `qa-password-123!`.
- **QA World** (id 6, seed 424242, frequency 54, ~29,162 tiles, ~104
  spawnable regions) — used for the "joining places you in a region
  with room" and "no region UI leak" checks.
- **QA World (Fill Test)** (id 10, seed 111222, frequency 8, 642
  tiles) — resolves to **exactly two** spawnable regions. Used for
  "two accounts land in different regions" and "a full world turns
  new players away," since it can be filled by hand with two
  throwaway joins.

## What To Test

Browser-observable behaviors (primary QA surface):

- **Joining places you in a region with room** — log in as
  `qa@broken-oaths.test`, go to `/play`, click
  `[data-test='join-world-6']`. Expect redirect to `/play/6` with a
  rendered board, two units (Lord + Settler) in the unit panel, and no
  error. This is criterion 7411/7404's player-facing surface — the
  substrate work (region sizing, seed determinism) is validated by the
  BDD specs listed below; the browser check confirms spawn actually
  succeeds and lands the player on workable land.

- **Region boundaries are invisible (no region UI leak)** — on
  `/play/6`, inspect the rendered page (HTML source, sidebar if any,
  screenshot) for any region id, region border overlay, or
  region-derived color coding. Expect none — regions are a
  server-only concept. Cross-check against source: `play.ex` and
  `join.ex` templates should contain no `region` reference beyond
  generic prose/copy (e.g. the abandon-modal copy "region freed for
  another player" is fine; a rendered region id or boundary line is
  not).

- **Two different accounts land in different regions** — using QA
  World (Fill Test, id 10, exactly two spawnable regions): join as
  `qa@broken-oaths.test` first, screenshot the board. Register and
  confirm a throwaway account, join world 10 as them, screenshot their
  board. Since the world has only two spawnable regions, a successful
  second join proves it landed in the *other* one (if it had tried to
  reuse the first, `world_full?/1` would already read true after one
  join only if there were exactly one region — there are two, so this
  alone isn't fully conclusive from the UI). To make this conclusive,
  cross-check `Player.region_id` for both users via `iex -S mix`
  (`BrokenOaths.Repo` query or `Game` context lookup) and confirm the
  two values differ. Visually, the two boards should also show
  different camera centroids (different starting hemisphere) —
  screenshot both for evidence.

- **A full world turns new players away** — continuing on world 10
  (now both regions claimed by the two accounts above): register and
  confirm a third throwaway account, log in as them, go to `/play`.
  Expect `[data-test='world-full-10']` ("Full") badge instead of a
  join button — confirm no `join-world-10` button is rendered for this
  user. If a join is attempted anyway (e.g., stale picker view —
  reload then click quickly), expect
  `[data-test='join-error']` to render "That world just filled up —
  pick another." (exact string, `join.ex:111`) and confirm the third
  user has no region in world 10 afterward: `/play/10` should bounce
  them back to `/play` (per `GameLive.Play.mount/3`'s
  `claimed_region == nil` redirect).

Code/spec-level criteria (not independently browser-testable — no UI
surface exists to assert against; confirmed by reading the BDD spec
files below rather than re-derived by hand):

- Same seed always produces the same region partition (criterion
  7404) — `test/spex/877_.../criterion_7404_..._spex.exs`, pure
  function of `world.seed`/`world.frequency`, cached in
  `:persistent_term`.
- Every land/coastal tile belongs to exactly one region; deep ocean
  belongs to none (criterion 7405).
- Simultaneous joins never double-claim a region (criterion 7407) —
  requires true concurrent requests, not reproducible by sequential
  manual clicks; the spec drives this with concurrent `Task`s against
  `WorldServer`.
- Undersized island regions are never offered for spawning (criterion
  7408) — the 175-tile habitability floor in `Regions.spawnable/1`.
- Mountains and coastal water count as country space (criterion 7410)
  — `Regions.tile_class/2` classification.
- A claimed region has room for about seven cities (criterion 7411) —
  `@target_region_size 250` in `Regions.ex`; no cities feature exists
  yet to observe this against in the UI.

For these six, this QA pass treats "the spec file exists, is named for
the criterion, and the story's linked component (`GameLive.Join`) has
a passing test suite" as sufficient evidence, and will spot-check with
`iex` (e.g. `Regions.partition(world) |> Map.values() |> Enum.map(&length/1)`
to eyeball region sizes cluster near 250, none far below 175) rather
than re-litigate them as full manual scenarios.

## Result Path

Findings are filed via `create_issue` as discovered; the run concludes
with one `submit_qa_result` call against task id
`36abe432-16fc-4771-b53d-740e0fd3f410`. Screenshots go in
`.code_my_spec/qa/877/screenshots/`.

## Setup Notes

- `mix run priv/repo/qa_seeds.exs` triggered an out-of-band recompile
  (90 files) at the start of this session — the exact trigger the plan
  documents for the "500 on every route" failure mode. Re-probed
  immediately after: `/play` still 302, `/` still 200, `/health` still
  200 — server survived this compile without needing a restart. Noting
  this in case it recurs mid-session for a different reason.
- The dev server *was* found already 500ing on every route except
  `/health` at the very start of this QA run (stale `_build/dev`
  before this session's own seed-triggered recompile). Team lead
  restarted it before work began; confirmed 200/302 before proceeding.
- No region id, region boundary, or region-derived color/overlay
  exists anywhere in `play.ex`/`join.ex` templates per source read —
  the "no UI leak" scenario above is expected to pass; if it doesn't,
  that's a real regression against server-owned-region design intent,
  not a matter of taste.
