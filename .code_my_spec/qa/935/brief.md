# Qa Story Brief

## Tool

web

## Auth

Log in via the browser (Vibium MCP) at `http://localhost:4050/users/log-in`
using the password form (`#login_form_password`), per `.code_my_spec/qa/plan.md`.
Two accounts, both password `qa-password-123!`:

- Lord: `qa-913-demo@broken-oaths.test`
- Vassal: `qa-913-rival@broken-oaths.test`

Scroll `#login_form_password` into view first, fill
`#login_form_password_email` (skip if `readonly` — re-auth mode) and
`#user_password`, then click the "Log in and stay logged in" button inside
`#login_form_password`.

To view both sides at once, either use two browser sessions (Vibium
`browser_new_page`/`browser_switch_page`) or log out
(`a[href='/users/log-out']`) and back in between checks.

## Seeds

No fresh seed run needed — reuse existing DB state, do not re-run
`mix run priv/repo/qa_seeds_rebellion.exs` this session (it unconditionally
resets "QA World (Rebellion Demo)" and 5 other concurrent QA sessions
(stories 936-940) may depend on that world's current tyrant/demo
vassalage staying put).

Confirmed via `psql broken_oaths_dev` before testing (2026-08-21): world id
**7** ("QA World (Rebellion Demo)") is `paused: true`, stale since
2026-07-26 (no recent activity from other sessions). It already has an
**active** `game_vassalages` row (id 13) unrelated to the tyrant/demo pair
other stories use:

- `lord_player_id: 19` (qa-913-demo, world player), `vassal_player_id: 20`
  (qa-913-rival), `tribute_rate: 0.25` (baseline), `oath_strain: 0`.

Use THIS lord/vassal pair (demo=lord, rival=vassal) for every scenario
below — it's isolated from the tyrant-demo relationship (game_vassalages
id 4, status `broken`) that the concurrent Protection Pact / Declare
Independence / Rebellion sessions are centered on. World URL: `/play/7`.

If contention is suspected at any point, re-check state first with
`curl http://localhost:4050/dev/qa/worlds/7` (expect `paused: true`)
before using `/dev/qa/worlds/7/step` — do not `resume` this world.

## What To Test

- **Criterion 2661 (both sides see the same gauge):** Log in as the lord
  (demo), open the "Vassals" dropdown (`[data-test=vassals-list]`), find
  the rival's row (`[data-test=vassal-row-<rival_user_id>]`) and read
  `[data-test=vassal-oath-strain]`. Log in as the vassal (rival) and read
  `[data-test=my-oath-strain]` in the top bar. Confirm both numbers match
  at every step below.
- **Criterion 2662 (high tribute rate drifts strain upward over time):**
  As lord, submit the `set_tribute_rate` form for the rival at a rate
  well above the 25% baseline (e.g. 80). Step one turn
  (`curl -X POST http://localhost:4050/dev/qa/worlds/7/step`) and confirm
  `oath_strain` rose (both views). Step 2-3 more turns and confirm it
  keeps rising while the rate stays elevated.
- **Criterion 2665 (strain does not swing within a single turn):** During
  the drift steps above, confirm the delta per single `/step` call is
  small and bounded (at most ~2 points), never a big jump — read
  `[data-test=oath-strain-drivers]` in the lord's vassal row for the
  "Driven by tribute rate" context text.
- **Criterion 2663 (an unhonored Protection Pact spikes strain):** As
  vassal (rival), click `[data-test=mark-pact-unhonored]` in the top bar.
  Confirm strain jumps immediately (no turn step needed) by a large,
  one-time amount, then check the lord's view reflects the same new
  value.
- **Criterion 2664 (lord concessions ease strain):** As lord, with strain
  elevated from the above, click `[data-test=gift-vassal]` (Gift) and/or
  `[data-test=declare-shared-enemy]` (Shared Enemy, only visible if a
  known third player exists) and/or `[data-test=honor-protection-call]`
  on the rival's row. Confirm strain drops after each action (both
  views).
- **Criterion 2666 (max strain never auto-rebels):** Push strain to 100
  (repeat `mark-pact-unhonored` and/or high-rate drift steps until it
  clamps at 100 — confirm it never exceeds 100). With strain at 100,
  confirm nothing auto-fires: no rebellion prompt/notification appears
  for either account, and a DB check
  (`psql broken_oaths_dev -c "select status from game_vassalages where id = 13;"`)
  still shows `active` — the vassalage is not auto-severed. Declaring
  independence must remain a deliberate, separate player action (do not
  actually declare independence — that's out of scope for this story and
  would consume the shared world's rival relationship other sessions may
  still want intact).
- Explore: try setting the tribute rate back to exactly 25% (baseline)
  and step a turn — confirm strain does NOT drift at all when the rate
  sits exactly on baseline (per `OathStrain.tribute_drift/2`'s
  "contributes nothing at baseline" behavior).
- At the end, as a courtesy to other concurrent sessions, use Gift/Shared
  Enemy/lowered tribute rate to bring strain back down somewhat rather
  than leaving it pinned at 100 (best-effort, not a hard requirement).

## Result Path

Findings are filed via `create_issue` as discovered and the session ends
with one `submit_qa_result` call — no result.md file (see
`.code_my_spec/qa/plan.md` and the `qa_story` playbook). Screenshots go to
`.code_my_spec/qa/935/screenshots/`.

## Setup Notes

`BrokenOaths.Feudal.OathStrain` (source:
`lib/broken_oaths/feudal/oath_strain.ex`) is pure math; the imperative
shell applying it lives in `BrokenOaths.Feudal.OathStrain.Ledger`
(`lib/broken_oaths/feudal/oath_strain/ledger.ex`), invoked once per raw
turn from `WorldServer.run_tick/1`
(`lib/broken_oaths/simulation/world_server.ex:1888`) — drift is NOT
gated by the `economy_turns` boundary, so every `/step` call is expected
to move strain (when off-baseline). UI lives in
`lib/broken_oaths_web/live/game_live/feudal_top_bar.ex`: vassal's own
view around line 227 (`my-oath-strain`), lord's per-vassal view around
line 664 (`vassal-oath-strain`) plus the drivers breakdown at line 673
and the concession buttons at lines 696-745.
