# Qa Story Brief

## Tool

web (`vibium` CLI against `/play/:id`, per plan.md's "MCP browser tools
are unreliable" guidance — NOT the MCP `browser_*` tools) plus the
dev-only `/dev/qa/worlds/:id/*` control surface (curl) to construct a
deterministic scenario. Every UI assertion is cross-verified against a
`psql broken_oaths_dev` read of the same data immediately after. No
`:api`-pipeline testing needed — Protection Pact has no controller/API
surface, only LiveView, plus the transient in-memory `protection_calls`
WorldServer state that only the LiveView (not any DB table) exposes.

## Auth

Same confirmed lord/vassal pair as the prior QA pass, world 3 ("QA
World (Multiplayer)"):

- Lord: `qa-901-a@broken-oaths.test` / `qa-password-123!` (player id 11,
  user id 11)
- Vassal: `qa-901-b@broken-oaths.test` / `qa-password-123!` (player id
  12, user id 12)

```
vibium go "http://localhost:4050/users/log-in"
vibium fill "#login_form_password_email" "qa-901-a@broken-oaths.test"
vibium fill "#user_password" "qa-password-123!"
vibium click "#login_form_password button[name='user[remember_me]']"
```

Repeat with the `-b` account (log out via `a[href='/users/log-out']`
first) to see the vassal's own view. Run vibium with the sandbox
disabled (plan.md "Sandbox blocks the vibium daemon socket").

## Seeds

Already seeded — do not run `mix run`/`iex -S mix` this session
(plan.md: a second BEAM process can recompile and wedge the shared dev
server). Confirmed current state via `psql broken_oaths_dev`:

- World 3: paused (`turn: 433`, `paused: true`) — safe, no wall-clock
  drift risk.
- `game_vassalages` id 2: lord_player_id 11 → vassal_player_id 12,
  `oath_strain: 15`, status active — the pair under test. (id 3 is the
  reverse direction, lord 12 → vassal 11, oath_strain 0 — leave alone.)
- `game_players`: player 11 (lord) honor 98, gold 329; player 12
  (vassal) honor 100, gold 10.
- Player 11 units: warriors #441 (tile 259), #443 (tile 265), lord #212
  (tile 506).
- Player 12 units: worker #490 (tile 258, 10 HP — fragile, avoid as an
  attack-bait target this session since a dead defender mid-window is
  an untested edge case), lord #214 (tile 266), warrior #444 (tile 504,
  100 HP), warrior #459 (tile 101, 100 HP).
- `config :broken_oaths, :feudal_enabled` reads `true` in `dev.exs` —
  confirmed, no need to re-check unless AC1 unexpectedly never fires.

## What To Test

**Context for this run**: issue 9cb08e92 (filed in the prior 936 QA
pass) found that the REAL turn-tick barbarian AI
(`BarbarianPhase.resolve_barbarian_attack/4`) never called
`ProtectionPact.maybe_raise_protection_call/3` — only a test-only
bridge did — so AC1's barbarian-trigger sub-case silently never fired
in real gameplay. That issue is now marked resolved: the fix wires the
same two `ProtectionPact` hooks `Resolver.resolve_attack/4` already
used directly into `barbarian_phase.ex:263-265`, with `state.turn`
bumped to `new_turn` immediately before them so the raised call's
deadline isn't stamped one turn stale. **Primary goal this session**:
prove that live, through the browser, not just via source trace.
`protection_calls` is transient WorldServer state with no backing DB
table — the LiveView page is the only surface that exposes it, so this
cannot be confirmed by `psql` alone; screenshot + `get_text`/`get_html`
against `/play/3` is the load-bearing assertion for AC1/AC2, with
`psql` used to cross-verify the downstream oath_strain/honor writes on
AC3/AC4.

- **AC1 trigger (barbarian real turn-tick path — THE regression
  target)**: Baseline screenshot of `/play/3` as lord `qa-901-a`,
  confirm `[data-test='vassal-row-12']` has NO
  `[data-test='protection-call']` child yet. Spawn a camp-tied
  barbarian adjacent to vassal player 12's warrior #459 (tile 101):
  `POST /dev/qa/worlds/3/barbarians -d tile_id=94 -d camp_id=48` (this
  exact combo reproduced the bug cleanly last session). `POST
  /dev/qa/worlds/3/step` once. Confirm via `psql` that combat actually
  resolved (barbarian and/or warrior #459 HP changed from 120/100).
  Then reload `/play/3` as lord and confirm
  `[data-test='vassal-row-12']` NOW contains
  `[data-test='protection-call']` with a `[data-test='protection-window']`
  countdown reading a small positive integer (window_remaining, ≤3).
  Screenshot.
- **AC2 visibility (both sides, with countdown)**: With the call still
  pending, log in as vassal `qa-901-b`, navigate `/play/3`, confirm
  `[data-test='my-protection-call']` is visible with
  `[data-test='my-protection-window']` showing the same countdown
  value (or one tick lower if a turn passed in between). Screenshot
  both the lord's and the vassal's view side by side.
- **AC3 honored (lord relieves the siege in time)**: `PATCH
  /dev/qa/worlds/3/units/427-ish-barbarian_id -d hp=1` (use the id
  returned by the `POST .../barbarians` call above) to guarantee a
  one-hit kill. As lord, use `.code_my_spec/qa/scripts/board_state.sh`
  to confirm warrior #459's movement/adjacency to the barbarian's tile
  (`PATCH /dev/qa/worlds/3/units/459 -d recharge=true` first if
  needed), then `board_click.sh 101 left` (select #459) followed by
  `board_click.sh <barbarian_tile> right` (attack order). `POST
  /dev/qa/worlds/3/step` to resolve. Expect: barbarian HP → 0 (`psql`),
  the pending call gone from `[data-test='vassal-row-12']`, vassalage
  id 2's `oath_strain` eased below 15 (`psql` — `OathStrain.
  ease_shared_enemy/1`'s exact formula, read the actual before/after),
  and lord 11's honor up by exactly 3 (98 → 101, `honored_honor_gain/0`)
  both via `psql` and via `[data-test='player-honor']` in the UI.
- **AC4 broken (lord ignores the call)**: Trigger a second, independent
  call against warrior #444 (tile 504, 100 HP — not the fragile
  worker, so it survives repeated barbarian attacks across the window
  without dying and complicating the read). Use `board_state.sh 504`
  to find a vacant adjacent tile, spawn a barbarian there
  (`POST .../barbarians -d tile_id=<adjacent> -d camp_id=<any>`),
  `step` once to confirm the second call raises (same AC1-style check).
  Then take NO defensive action — `POST /dev/qa/worlds/3/step` twice
  more (response_window is 3 turns total, confirmed in
  `protection_pact.ex`'s `@response_window 3`) with no lord response.
  Expect after the 3rd step: the call auto-resolves broken
  (`apply_protection_pact_ticks/1`) — vassalage id 2's `oath_strain`
  spikes sharply via `OathStrain.spike_broken_protection_pact/1`
  (`psql`, read the exact before/after), lord 11's honor drops by
  exactly 5 (unclamped, `broken_honor_penalty/0`), and the call
  disappears from both UIs (resolved, not pending). World 3 has only
  one vassal for lord 11, so the realm-wide contagion spike
  (`spike_contagion/1`) has no OTHER vassal to apply to this
  session — note that as expected/untestable-here rather than a gap.
- **AC5 net-positive shape (qualitative, live-observed this time)**:
  Across the AC3 (honored) and AC4 (broken) sequences just run,
  confirm live that oath_strain moved in OPPOSITE directions (down on
  honored, up sharply on broken) and lord honor moved the same way (up
  3 on honored, down 5 on broken) — the same shape
  `criterion_7730_..._spex.exs` and `protection_pact_test.exs` already
  prove numerically end-to-end; this session confirms the shape is
  visible through the real UI + DB, not the precise magnitudes (those
  are already covered by the passing automated suite).

## Result Path

No result.md — findings via `create_issue`, outcome via
`mcp__plugin_codemyspec_cms_cloud__submit_qa_result`. Screenshots to
`.code_my_spec/qa/936/screenshots/`.

## Setup Notes

- Do not touch world 7 (rebellion-arc, in concurrent use by other QA
  sessions) or worlds other than 3. World 1 (`paused: false`,
  `turn_started_at` today) and world 2 (`paused: false`, stale
  `turn_started_at` from 2026-07-24) are outside this story's scope —
  leave them alone; if either is ever touched, pause it first per
  plan.md's WorldServer catch-up System Issue.
- Concurrent QA agents 937/940 may be running browser sessions this
  session per the task brief — if `vibium` contention appears despite
  the CLI+psql approach (per plan.md's documented mitigation), stop and
  message the team lead rather than fighting it silently.
- `data-test="vassal-row-#{vassal_user_id}"` — confirmed player_id ==
  user_id for both seeded accounts in world 3 (11 and 12), so
  `vassal-row-12` is correct without an extra lookup.
