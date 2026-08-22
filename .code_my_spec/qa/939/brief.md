# Qa Story Brief — 939 Lord's Death — Seize the Moment

## Tool

web (Vibium MCP browser tools) for every criterion — this story is entirely
LiveView-surfaced (`GameLive.Play`'s feudal top bar). `curl` against the
dev-only `/dev/qa/worlds/:id/*` control surface (see `.code_my_spec/qa/plan.md`)
is used only for scenario setup (pause, spawn barbarian, set HP, step turns),
never as a substitute for verifying the actual rendered prompt.

## Auth

Reuse the already-seeded, already-vassalized pair from
`priv/repo/qa_seeds_rebellion.exs` (world 7, "QA World (Rebellion Demo)") —
do NOT re-run that seed script (mix run is banned mid-session per plan.md;
also the world's Vassalage between these two is already real/active, no
reseed needed):

- Lord: `qa-913-demo@broken-oaths.test` / `qa-password-123!` — Player id 19,
  Lord unit id 492 (tile 441, hp 150 at scenario start).
- Vassal: `qa-913-rival@broken-oaths.test` / `qa-password-123!` — Player id
  20, vassal of player 19 (`game_vassalages` id 13, status `active`,
  tribute_rate 0.25).
- Password login: `/users/log-in`, scroll `#login_form_password` into view,
  fill `#login_form_password_email` / `#user_password` (skip email fill if
  the field is `readonly` — that means a re-auth session is already
  present in the shared browser; see Setup Notes).
- World: `/play/7`.

Ignore the world's OTHER pre-seeded actor, `qa-913-tyrant@broken-oaths.test`
(player 18) — historical/decorative seed state for the Beat 1-4 demo video,
unrelated to this story's own lord/vassal pair (19 -> 20) and safe to leave
untouched.

## Seeds

No new seeding required. World 7 was already seeded by
`priv/repo/qa_seeds_rebellion.exs` in a prior session; do not re-run it
(mix run is banned during a live QA session per plan.md's own System
Issues — risk of crashing the shared dev server for all concurrent
sessions). Confirm current state first, read-only:

    curl -s http://localhost:4050/dev/qa/worlds/7
    psql broken_oaths_dev -c "select id, lord_player_id, vassal_player_id, status, tribute_rate from game_vassalages where world_id=7;"

Expect `paused: true`. If turn has drifted far from the low starting value
(~11) since a prior session, another agent may be actively driving this
world — pick a different vassalage/world rather than fighting over it.

## What To Test

Setup (via DevQA control surface, world already paused so no clock races):

1. Confirm world 7 is paused: `GET /dev/qa/worlds/7`.
2. Find a tile adjacent to the demo lord's Lord unit (tile 441) — via a
   logged-in board session's client-side geometry (`board_state.sh 441`,
   or the equivalent `browser_evaluate` against the board hook — see
   `.code_my_spec/qa/scripts/board_state.sh`'s own adjacency technique).
3. `POST /dev/qa/worlds/7/barbarians -d tile_id=<adjacent_tile>` to spawn a
   killer.
4. `PATCH /dev/qa/worlds/7/units/492 -d hp=1` — lethal setup so the next
   barbarian hit is guaranteed fatal regardless of damage roll (mirrors the
   BDD spex's own `Fixtures.set_unit_hp/3` convention). Do NOT set hp to 0
   directly and skip the barbarian — a direct HP patch does not go through
   the combat-kill pipeline that schedules `pending_heirs`, so it would
   silently fail to exercise criteria 7748/7749/7750.
5. `POST /dev/qa/worlds/7/step` (repeat as needed) until the barbarian's
   turn resolves an attack that kills the Lord unit.

Then, as the VASSAL (rival) in the browser:

- **Criterion 7743** — Navigate to `/play/7`. Assert
  `[data-test='seize-the-moment-prompt']` is visible and contains the
  literal text "Your lord has fallen — seize the moment", and that it
  contains a nested `[data-test='declare-independence-action']` button.
  Screenshot as evidence.
- **Criterion 7744** — Before clicking anything: assert
  `[data-test='vassal-status']` still reads "Sworn to
  qa-913-demo@broken-oaths.test" (oath not auto-broken). Read
  `[data-test='my-tribute-rate']` and `[data-test='vassal-oath-strain']`,
  step 1-2 more turns, re-read both — assert unchanged (no auto-buff).
- **Criterion 7745** — Click the `declare-independence-action` button
  inside the prompt. Assert the Vassalage severs (`vassal-status` badge
  disappears) and a rebellion starts (an `at-war-with`/rebellion panel
  appears on the LORD's own board). Whether the occupied city actually
  "rises" depends on the lord's Honor/tribute (story 915's own formula,
  out of scope to force deterministically here) — either outcome is
  consistent with "liberates through the normal path"; just confirm the
  SAME `declare_independence` action fired and produced Vassalage-severed
  + rebellion-active, not a bespoke leaderless-only code path.
- **Criterion 7746** — Step several more quiet turns. Assert the rebel's
  city HP/status is unchanged across them (no lordly counterattack is
  possible with the lord dead) and that no `[data-test='protection-pact']`
  element ever appears on the vassal's board.
- **Criteria 7748/7749** — End the war deterministically without depending
  on the probabilistic city-rise roll: while still logged in as the
  (dead-lorded) demo account, use the negotiated-peace path (story 919) —
  `offer_peace`/`accept_peace` between the two accounts, outcome
  `independence` — to resolve the rebellion. Step turns until
  `pending_heirs`' arrival turn passes (10 turns after the kill, per
  `HeirSuccession`/`barbarian_phase.ex`, but gated behind the active
  rebellion until it ends — see `BrokenOaths.Feudal.Rebellion.War.
  defer_gated_heirs/1`). Assert a NEW Lord unit (different id) appears on
  the demo player's capital tile, and that the rival still reads free
  (no `vassal-status` badge) — the dynasty continues minus the vassal who
  left.
- **Criterion 7750** — Separate, simpler scenario: any lone lord with NO
  vassals at all, killed the same lethal-barbarian way. Step turns and
  confirm a heir arrives at their capital within a short bound (the exact
  delay is an explicitly unlocked "Three Amigos" value per the story — do
  not assert a specific turn count) with the realm fully intact
  (`city-status` still free). If no spare lone-lord account is available,
  this can be checked on the SAME demo account timeline by observing that
  the pre-919 legacy heir mechanic (`schedule_heir_if_lord_fell`, 10 turns
  flat, vassal-unaware) still exists and independently would satisfy this
  criterion — note explicitly which path (legacy timer vs. new
  war-gated trigger) actually produced the observed heir.

## Result Path

Findings via `create_issue` as discovered (see workflow doc); final outcome
via `submit_qa_result`. No result.md file.

## Setup Notes

- **Shared browser session across concurrent QA agents**: the vibium
  browser instance backing these MCP tools is ONE process with ONE shared
  cookie jar across every concurrent agent in this session — `browser_new_page`
  opens a new tab but tabs share auth state, and the "current page"
  pointer/index list churns as other agents open/close/navigate pages
  concurrently, so index-based `browser_switch_page` calls can race and land
  on the wrong page between calls. There is no per-agent browser context/
  profile isolation exposed by the current tool surface. Practically: expect
  to find someone else's account already logged in; do not log anyone out
  to force your own login. Prefer short, minimal-round-trip bursts (navigate
  then act, rather than navigate/list/switch/act) to reduce the interleaving
  window. Treat unexplained auth-state weirdness as contention, not a story
  bug, unless reproduced with a clean, uncontended session.
- **World landmines**: worlds 1, 2, and 4 have `paused: false` with a
  `turn_started_at` stale by weeks — touching them (even a bare `GET
  /dev/qa/worlds/:id`) triggers the already-accepted issue `4f25b084`
  (long-idle unpaused world's synchronous catch-up wedges the app). Avoid
  them entirely this session; worlds 3, 5, 6, 7 are already paused and safe.
- `war.spec.md` (the linked component's spec file, referenced by this
  story's own task prompt) does not exist at
  `.code_my_spec/spec/broken_oaths/feudal/rebellion/war.spec.md` — only
  `stewardship.spec.md`/`steward_log.spec.md` exist in that directory. Flag
  as a docs gap, not a story bug.
