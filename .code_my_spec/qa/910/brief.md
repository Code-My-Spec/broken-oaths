# Qa Story Brief — 910 Feudal Stewardship

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) + dev QA control surface.

## Auth

- Player A: `qa-901-a@broken-oaths.test` / `qa-password-123!` — player_id 11
- Player B: `qa-901-b@broken-oaths.test` / `qa-password-123!` — player_id 12

## Seeds

World 3, players 11/12 are BOTH allied (`game_alliances`, accepted) AND mutually vassalized
(11 lord of 12 via relationship id=2; 12 lord of 11 via a fresh relationship id=3) — giving both
the lord/fellow-vassal channel and the ally channel to test stewardship through in the same
2-player world.

## What To Test

- With one player offline, log in as the other and confirm the "Steward: Collect Bank" button
  (`data-test="steward-collect-bank"`) appears in BOTH the Vassals panel (`vassal-row-*`) AND the
  Alliance panel (`alliance-panel`) rows for the offline party — 7686 (lord path).
- Click it via the LORD path: confirm the offline OWNER's own `gold`/`banked_gold` move (sweep to
  the owner), the STEWARD's own gold is untouched, and a `game_steward_logs` row is written with
  `steward_player_id`/`owner_player_id`/`action=bank_collect`/`amount` — 7686, 7689, 7695.
- Click it via the ALLY path with the roles reversed (log out, swap who's online) — confirm the
  SAME sweep-to-owner/steward-gets-nothing/logged behavior holds in the OPPOSITE direction —
  direct, live evidence for 7688 (symmetric ally stewardship).
- Confirm `data-test="steward-log"` on the OWNER's own session lists every action taken on their
  behalf (both directions accumulate correctly, scoped per-owner) — 7695.
- Verify structurally (code read + UI absence) that a vassal never gets a LORD-path steward
  affordance targeting their own lord: `vassals_panel` only ever renders for `Game.vassals(world,
  user)` — i.e. only shows relationships where the CURRENT user is the lord — so relationship
  id=2 (lord=11) never surfaces a steward button for player 12 to use against player 11; only the
  (separate, sanctioned) ally channel does — 7687.
- Confirm no click-through UI exists for production stewardship or emergency-defend
  (`steward_queue_production`, `steward_defend`, etc. are `handle_event` clauses only, with no
  button/form anywhere in `play.ex`'s render) — 7690-7694 remain event-tested only, per the task's
  own framing.

## Result Path

Findings filed via `create_issue`, verdict via `submit_qa_result` (task_id
`d912d533-87b4-44f7-811a-6e076136a203`). Screenshots at `.code_my_spec/qa/910/screenshots/`.

## Setup Notes

World 3's 2-player cap blocks "fellow vassal" stewardship (needs 3 players sharing one lord) and
"vassal cannot steward own lord" can only be shown by code/UI-absence reasoning, not a failed
click, since the button simply never renders for that direction. No click-through UI exists for
production stewardship or emergency defense — noted as a gap in UI coverage (not a missing
mechanic; the underlying `handle_event` clauses exist and are unit/spex-tested).
