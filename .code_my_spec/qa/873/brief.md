# Qa Story Brief

Story 873 — New Player Spawns in World.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Use the password form `#login_form_password` (not the magic-link form above it):
  - `input[name="user[email]"]`
  - `input[name="user[password]"]`
- Primary QA account: `qa@broken-oaths.test` / `qa-password-123!`
- Additional throwaway accounts are needed for multi-user scenarios (world-full,
  membership cap, abandon-and-reclaim). Register them at
  `http://localhost:4050/users/register` with any `name@example.test` email,
  then read the confirmation/magic-link email from the dev mailbox at
  `http://localhost:4050/dev/mailbox` (Swoosh local adapter — no real email
  is sent). Set a password via the settings page, or just use the magic
  link each time to log that throwaway user in.
- Driven with the `vibium` CLI (bash), not the vibium MCP tools (not present
  in this session): `vibium go <url>`, `vibium find <selector>`,
  `vibium click <selector>`, `vibium fill <selector> <text>`,
  `vibium screenshot` (always writes `~/Pictures/Vibium/screenshot.png` —
  the path argument is broken; copy the file aside per scenario). If vibium
  wedges: `pkill -f chrome-for-testing; pkill -x vibium; rm -f
  ~/Library/Caches/vibium/vibium.sock`, then `vibium go` again (it lands on
  `about:blank` after a restart — always re-navigate).

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent. Creates/confirms:

- QA user `qa@broken-oaths.test` / `qa-password-123!`.
- **QA World** (world id 6, seed 424242, frequency 54, ~29,162 tiles,
  ~104 spawnable regions) — the main world for spawn/gold/units/resume
  scenarios. Too large to fill by hand.
- **QA World (Fill Test)** (world id 10, seed 111222, frequency 8, 642
  tiles) — resolves to **exactly two** spawnable regions, both verified
  crash-safe (see Setup Notes below for why that verification mattered).
  Added for this story so "world just filled up" and
  abandon-and-reclaim are testable by hand: two throwaway joins fill it
  completely.

For the three-world membership cap, use QA World (id 6), QA World (Fill
Test) (id 10, after it's already full is fine — membership cap doesn't
require an open region), and one of the pre-existing worlds already on
`/play` (Emerald Wilds, Verdant Expanse, Golden Steppes, Jade Wilds, or
"JAMES IS A BOSS" — all frequency 54, all with plenty of open regions).
No need to seed a fourth fixture.

## What To Test

- **Registered player picks a world and spawns** — log in as
  `qa@broken-oaths.test`, go to `/play`, confirm QA World (id 6) shows a
  `[data-test='join-world-6']` button. Click it. Expect redirect to
  `/play/6` and a rendered board (canvas + turn bar + gold badge).

- **Spawn delivers a Lord and a Settler on workable land** — on `/play/6`
  after spawning, open the unit panel (`GameLive.UnitPanel`,
  `data-test='unit-panel'`) and confirm two units are listed with type
  labels "Lord" and "Settler" (text labels only — no crown icon exists in
  the current UI; the story text mentions a crown icon but the
  implementation renders a text label instead — note this as an
  observation, not a failure, per team lead guidance). Screenshot the
  board and the unit panel.

- **Fresh spawn shows 50 gold** — on the same first spawn, confirm the
  gold badge `[data-test='player-gold']` reads `50`.

- **Re-entering a joined world never re-spawns** — from `/play`, click
  `[data-test='join-world-6']` again (button now reads "Enter" once
  you're a member). Confirm no error, and confirm gold/units are
  unchanged from the first spawn (re-check `player-gold` and
  `unit-panel` counts — should still be exactly 2 units and 50 gold,
  not 4 units / 100 gold).

- **Returning player resumes where their civilization is** — navigate
  away (e.g. to `/play`) and back to `/play/6`. Confirm the board loads
  centered on the same units (camera is computed once at spawn from the
  unit centroid — screenshot before/after to eyeball that the view
  didn't reset to a different hemisphere).

- **Playing in two worlds at once** — join QA World (Fill Test, id 10) as
  the same `qa@broken-oaths.test` user (this claims one of world 10's two
  spawnable regions). Confirm both `/play/6` and `/play/10` are
  independently reachable, each showing its own gold/units, and that
  `/play` shows "Your civilization" badges plus "Enter" on both.

- **Picking a world that just filled up fails gracefully** — register a
  throwaway user and have them claim world 10's second (last) spawnable
  region. Now register and confirm a third throwaway user, log in as
  them, go to `/play`, and confirm world 10 shows
  `[data-test='world-full-10']` ("Full") instead of a join button. If a
  join is still attempted (e.g. by racing a stale picker view — reload
  then click quickly, or use two browser sessions), confirm
  `[data-test='join-error']` renders "That world just filled up — pick
  another." and the throwaway user has no region in world 10 afterward
  (they should not appear on `/play/10`, and `/play/10` should redirect
  them to `/play` if they try navigating there directly, per
  `GameLive.Play.mount/3`'s `claimed_region == nil` bounce).

- **A fourth world join is refused at the cap** — using a throwaway user,
  join three distinct worlds (QA World id 6, QA World Fill Test id 10 —
  membership counts even if world 10 is already full from a prior
  scenario, since the cap counts memberships not open slots — and one
  of the other pre-existing frequency-54 worlds). Attempt to join a
  fourth. Confirm `[data-test='join-error']` renders a message
  containing "three" (`"You can only play in three worlds at once."`)
  and that the three existing memberships are untouched (still show
  "Enter" on `/play`).

- **Abandoning wipes the civilization and reopens the region** — on
  `/play/6` (or `/play/10`), click `[data-test='abandon-world']`. Confirm
  a confirmation modal appears (not a native JS confirm — a DaisyUI
  modal with `Cancel` and `[data-test='abandon-confirm']` "Abandon
  Forever"). Click Cancel first and confirm the modal closes with no
  change. Repeat and click `abandon-confirm` this time. Confirm redirect
  to `/play`, and that the world no longer shows "Your civilization" /
  "Enter" for this user — it shows "Join" again (or "Full" if someone
  else already reclaimed it).

- **An abandoned region is a fresh start for its next claimant** — this
  is cleanest on world 10 (two regions, easy to fully observe): after
  one owning user abandons their region, confirm `/play` no longer shows
  `world-full-10` (assuming the other region is still free, or abandon
  both to fully reopen it), and that a different throwaway user can
  click `join-world-10` and spawn cleanly (fresh 2 units, 50 gold, no
  leftover state from the previous owner).

## Result Path

Findings are filed via `create_issue` as discovered (not written to a
result file); the QA run concludes with one `submit_qa_result` call
against task id `963c164a-a200-4c2a-8f31-3aff45cba7b8`. Screenshots go in
`.code_my_spec/qa/873/screenshots/`.

## Setup Notes

- The app was 500ing on every routed path except `/health`/`/up` at the
  start of this session (stale `_build/dev` after an out-of-band config
  compile, matching the plan's documented "System Issues" entry). The
  team lead restarted the server; routes are confirmed 200/302 as of
  writing. If this recurs mid-run, message the team lead rather than
  restarting it directly.
- **Critical bug found and fixed-around during brief-writing** (issue
  `6b8a69f3-d401-4cb7-b45f-ad3ceaf414e6`): the first version of the
  fill-test fixture (frequency 5) crashed `Spawner.central_land_tiles/2`
  with a `KeyError`, which crashed `world_full?/1`, which took down the
  *entire* `/play` picker for every user and every world the moment that
  world was `status: "active"`. Root cause: a `:land` tile fully
  enclosed by same-region `:mountain` tiles has no BFS path to the
  region boundary. Frequency 5-6 reproduced this on every seed tried;
  frequency 7-8 did not (spot-checked ten seeds each via a per-region
  dry-run probe). The broken world (id 7, "QA World (Full Test)",
  frequency 5, seed 500555) is left in the DB `status: "archived"` as a
  standing repro case for the fix — **do not reactivate it**, it will
  immediately re-break `/play`. The safe replacement is QA World (Fill
  Test), id 10, frequency 8, seed 111222.
- The vibium daemon failed to start under the default sandbox (socket
  path is under `~/Library/Caches/vibium/`, not in the sandbox's
  writable allowlist). All vibium commands in this session ran with the
  sandbox disabled for that reason.
- `/play/:id` (`BrokenOathsWeb.GameLive.Play`) is the actual "board" this
  story is about — gold, abandon, and the unit panel all live there. The
  QA plan's `?mode=classic` / `toggle_sidebar` detail applies to the
  separate `/worlds/:id` (`WorldLive.Show`) globe-viewer feature, not
  this one; don't conflate the two when testing.
- The canvas board has no tile DOM (per plan). Verification here relies
  on the DOM chrome (turn bar, gold badge, unit panel, join/abandon
  buttons/modal) and screenshots, not on tile-level pixel assertions.
