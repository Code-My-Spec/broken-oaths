# Qa Story Brief

Story 873 — New Player Spawns in World. **Re-run** to confirm spawn/join/
re-entry/multi-world/abandon behaviors still hold after the city-loop
landed and units were HP-rescaled (Lord 150/150, Settler 50/50 — not the
old 100/100).

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Use the password form `#login_form_password` (not the magic-link form
  above it):
  - `input[name="user[email]"]`
  - `input[name="user[password]"]`
- Primary QA account: `qa@broken-oaths.test` / `qa-password-123!`
- Throwaway accounts needed for the fill/cap/abandon-reclaim scenarios:
  register at `http://localhost:4050/users/register` (email-only form,
  `#registration_form`, field `input[name="user[email]"]`) — this sends a
  login-instructions link, no password is set at registration. Read it
  from the dev mailbox at `http://localhost:4050/dev/mailbox` (Swoosh
  local adapter, no real email sent) and click the link to confirm +
  log that user in.
- Driven with the `vibium` CLI (bash), not MCP browser tools (not present
  in this session): `vibium go <url>`, `vibium find <selector>`, `vibium
  click <selector>`, `vibium fill <selector> <text>`, `vibium screenshot`
  (always writes `~/Pictures/Vibium/screenshot.png` — the path argument
  is broken; copy the file aside per scenario). Run with the sandbox
  disabled (`dangerouslyDisableSandbox: true`) — the daemon socket lives
  under `~/Library/Caches/vibium/`, outside the sandbox writable
  allowlist. If vibium wedges: `pkill -f chrome-for-testing; pkill -x
  vibium; rm -f ~/Library/Caches/vibium/vibium.sock`, then `vibium go`
  again (lands on `about:blank` after a restart — always re-navigate).

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent — safe to re-run, reuses existing records. No new seeds are
required for this re-run; use current DB state (confirmed via psql
before writing this brief):

- QA user (user_id 1, `qa@broken-oaths.test`) is currently a member of
  **world 6** ("QA World", player_id 1, lord unit 1 @ tile 7214, settler
  unit 2 @ tile 21635, gold 50, no city) and **world 10** ("QA World
  (Fill Test)", player_id 7, lord unit 13 @ tile 581, settler unit 14 @
  tile 575, gold 50, no city). **Do not abandon or found a city in world
  6** — later QA sessions (878-883) need that civilization intact.
- World 10 (frequency 8, exactly 2 spawnable regions: 0 and 1) is
  **already completely full** as of this session: region 0 held by QA
  user (player 7), region 1 held by `throwaway1@example.test` (user 3,
  player 3). This is convenient — the "world just filled up" scenario
  can be exercised immediately against a genuinely full world without
  needing to fill it by hand first.
- Other active worlds with plenty of open regions (frequency 54 each):
  id 1 Jade Wilds, id 2 Golden Steppes, id 3 JAMES IS A BOSS, id 4
  Verdant Expanse, id 5 Emerald Wilds. `throwaway2@example.test` (user
  4) is already a member of worlds 4, 5, 6 (previously used for cap
  testing) — don't reuse that account for the cap test this run, it's
  already at the 3-world ceiling with no headroom to demonstrate a
  *successful* 3rd join. Use the QA user (currently at 2 memberships)
  for the cap test instead.
- World 7 "QA World (Full Test)" is archived (deliberate Spawner-crash
  repro) — do not reactivate it.

## What To Test

- **Cap test (criterion 7437, "fourth world join refused")** — as
  `qa@broken-oaths.test` (2 memberships: worlds 6, 10), go to `/play`,
  click `[data-test='join-world-1']` (Jade Wilds) — expect success,
  redirect to `/play/1`, fresh Lord+Settler spawn (3rd membership).
  Return to `/play`, click `[data-test='join-world-2']` (Golden
  Steppes) — expect **no navigation**, `[data-test='join-error']`
  rendering a message containing "three". Verify via psql no
  `game_players` row exists for `user_id=1, world_id=2`, and that the
  three existing memberships (6, 10, 1) are untouched.

- **Fill / graceful-full test (criterion 7413)** — register + confirm a
  throwaway account (e.g. `qa873-fillb@broken-oaths.test`). Log in as
  them, go to `/play`. World 10 should render
  `[data-test='world-full-10']` ("Full" badge) with **no** join button,
  since both its regions are already claimed. Screenshot. This
  demonstrates the picker fails gracefully (no crash, no button to even
  attempt the join) against a full world. Also try navigating directly
  to `http://localhost:4050/play/10` as this non-member — expect a
  bounce back to `/play` (per `GameLive.Play.mount/3`'s
  `claimed_region == nil` redirect), not a crash or a spawn.

- **Abandon test (criterion 7439, "abandoning wipes the civilization and
  reopens the region")** — log back in as `qa@broken-oaths.test`, go to
  `/play/10` (Enter). Click `[data-test='abandon-world']` — expect a
  DaisyUI confirmation modal (not a native JS confirm), `Cancel` and
  `[data-test='abandon-confirm']` ("Abandon Forever"). Click `Cancel`
  first, confirm modal closes with no change (still on `/play/10`,
  units still present). Click abandon again, then
  `abandon-confirm`. Expect redirect to `/play`. Verify via psql: the
  `game_players` row for `user_id=1, world_id=10` and its `game_units`
  rows (cascade delete) are gone. On `/play`, world 10 should now show
  `[data-test='join-world-10']` ("Join") for the QA user, not "Enter".

- **Fresh-claim test (criterion 7440, "abandoned region is a fresh start
  for its next claimant") + registered-player-spawns (7412) + spawn
  stats (7417, 7418)** — log back in as `qa873-fillb@broken-oaths.test`
  (the throwaway from the fill test, which failed to join earlier). Go
  to `/play` — world 10 should no longer show "Full"; it should show
  `[data-test='join-world-10']`. Click it — expect success, redirect to
  `/play/10`. Screenshot the board and
  `[data-test='unit-panel']`. Confirm:
  - Two units present, `[data-test='unit-type']` reading "Lord" and
    "Settler" (text labels — no crown icon in the current UI; note as
    observation only, not a defect, matching earlier QA guidance).
  - `[data-test='unit-hp']` reads "HP 150/150" for the Lord and "HP
    50/50" for the Settler (HP-rescale sanity — criteria implied by the
    story's pre-city substrate, verify the new numbers, not the old
    100/100).
  - `[data-test='player-gold']` reads `50`.
  - Spawn tile terrain is workable land (not ocean/mountain) — confirm
    via psql `terrain` lookup for the new lord/settler `tile_id`s (see
    Setup Notes for how) or via the sidebar/tile info if exposed.
  - Via psql: the new `game_players`/`game_units` rows are fresh
    (new ids, not reusing QA user's old player_id 7 / unit ids 13-14),
    gold is exactly 50, and no leftover orders/improvements reference
    the old player.

- **Re-entry never re-spawns (criterion 7414) + resume (criterion
  7415)** — as `qa@broken-oaths.test`, from `/play` click
  `[data-test='join-world-6']` (now labeled "Enter"). Confirm redirect
  to `/play/6`, and via UI + psql that the SAME units appear (lord unit
  id 1 @ tile 7214, settler unit id 2 @ tile 21635 — or wherever they've
  since moved if orders were queued in a prior session; the point is
  **same unit ids**, not a fresh pair), gold still 50 (no city built,
  so no accrued income to complicate the check), HP still 150/150 /
  50/50. Screenshot. Then navigate to `/play` and back to `/play/6` —
  screenshot again and confirm the camera/board renders the same
  location (units at the same tiles, not reset to a different
  hemisphere) — camera is computed once from the unit centroid at
  mount, so this is really "same units visible" not a pixel-perfect
  camera diff.

- **Multi-world isolation (criterion 7416)** — as `qa@broken-oaths.test`,
  on `/play/1` (the Jade Wilds civ joined during the cap test), select
  a unit (left-click) and queue a movement order (right-click an
  adjacent land tile) if the board interaction allows it in the time
  available. Snapshot `game_units`/`game_orders` for world 6 via psql
  immediately before and after this interaction — confirm zero rows
  changed for world 6. If queuing an order proves fiddly against the
  canvas board within a reasonable time-box, a plain snapshot-diff
  across worlds 1/6/10 (confirm units/gold in each are exactly what
  psql shows independently, with no cross-contamination) is acceptable
  evidence — note which approach was used.

- **HP rescale sanity** — already covered above (both the world-1 fresh
  spawn during the cap test and the world-10 fresh-claim spawn), plus
  the world-6 re-entry check. No separate pass needed; call out
  explicitly in the scenario record.

- **Registered player picks a world and spawns (criterion 7412)** —
  exercised end-to-end by the cap test's world-1 join and the
  fresh-claim world-10 join above. Call it out explicitly in the
  scenario record rather than re-doing it separately.

## Result Path

Findings are filed via `create_issue` as discovered (not written to a
result file); the QA run concludes with one `submit_qa_result` call
against task id `fa927cec-92fd-4775-8363-316a40a0325f`. Screenshots go
in `.code_my_spec/qa/873/screenshots/`.

## Setup Notes

- This is a re-run of a previously-passing QA session (see prior
  `brief.md` git history / prior screenshots in this directory) — the
  goal is to confirm the same behaviors after the city-loop landed and
  units were HP-rescaled, not to re-derive the flow from scratch.
- `psql broken_oaths_dev` requires the sandbox disabled
  (`dangerouslyDisableSandbox: true`) per the QA plan.
- Never call `BrokenOaths.Game.*` from a separate `iex -S mix` process
  while the dev server is running (competing `WorldServer` GenServer
  risk). Use psql for raw table reads and the browser/UI for anything
  that requires the live `Game` context (join, abandon, world-full
  checks) — the UI's Full/Join badges are the authoritative "is this
  world full" signal, not an iex call.
- Terrain lookup for a tile id: `psql broken_oaths_dev` has no terrain
  table (terrain is computed from `worlds.seed` + `worlds.frequency` via
  `BrokenOaths.Worlds.Generator`/`Terrain`, which are pure and iex-safe)
  — if a UI terrain label isn't visible, it's acceptable to note "not
  ocean/mountain, per successful non-crashing spawn" as inference rather
  than blocking on a terrain readout, since `Game.join_world/2` already
  guarantees workable land by construction (spawn tile selection lives
  in `Spawner.central_land_tiles/2`).
- The dev server is already running at `http://localhost:4050` — do not
  restart it, do not run `mix phx.server`, do not run
  `mix compile`/`mix format` (shared `_build/dev`, causes a
  config-reload 500 outage across every route).
- Turn boundary is 60s wall-clock in dev — movement orders won't
  resolve instantly; the isolation test only needs the order to be
  *queued* (a `game_orders` row written), not resolved.
