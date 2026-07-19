# Qa Story Brief — 908 Tribute Payments

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) for state verification + dev QA control surface (`/dev/qa/worlds/3/step`) to advance deterministic turns.

## Auth

Same two accounts as 906/907, password `qa-password-123!`:

- Player A (lord): `qa-901-a@broken-oaths.test` — player_id 11
- Player B (vassal): `qa-901-b@broken-oaths.test` — player_id 12

## Seeds

Depends on the active Vassalage row created in 907 (World 3, lord=11, vassal=12).

## What To Test

- Log in as player A, open the Vassals dropdown, submit the "Set Rate" form to raise the rate from 25% to 40% — verify via psql (`game_vassalages.tribute_rate`) it persists, and the vassal's own status-bar rate badge (player B's session) reflects the new value — criterion 7673.
- Record baseline `game_players.gold` for both players and `game_gold_logs` row count (world 3).
- Advance the world with `POST /dev/qa/worlds/3/step` at least 3 times (confirm via `GET /dev/qa/worlds/3` that `turn` actually advances, and cross-check the vassal's production `banked` progress increases — proof the tick genuinely ran).
- After each step, re-check `game_players.gold` and `game_gold_logs` for a tribute transfer — criteria 7674 (12g/turn @ 25% = 3g), 7675 (raised rate applied next boundary), 7676 (debt on empty treasury).
- Attempt to issue a call to arms from the Vassals panel UI — expected an "Issue Levy" affordance per criterion 7677/7678. **Actual: none exists** (only a passive `levy-status` badge).
- As a workaround, drive `hook.pushEvent("issue_levy", ...)` directly. Since World 3 has only 2 players (no legal third `target_player_id` exists — `issue_levy` requires a target distinct from both lord and vassal), only the negative/validation path is testable in this world: confirm targeting the vassal themselves is correctly rejected (no `game_levies` row created).
- Document that the full positive path (issue against a real third party, vassal answers/refuses, Oath Strain spike on refusal) could not be exercised live in this environment.

## Result Path

Findings filed as issues via `create_issue`, final verdict submitted via `submit_qa_result` (task_id 567773d8-73fd-4f95-837e-9587329fc5bf). Screenshots at `.code_my_spec/qa/908/screenshots/`.

## Setup Notes

Gold tribute (criteria 7674/7675/7676) is architecturally gated behind a per-turn "gold income" figure that is only ever populated by a test-only GenServer seam (`:set_player_gold_income_for_test`), never exposed via the dev QA HTTP surface or any LiveView event — confirmed by code inspection AND by empirically stepping 3 real turn boundaries with an active, high-rate (40%) vassalage in place and observing zero gold movement / zero gold-log rows the entire time (see filed issue 589386f2).

Call-to-arms (criteria 7677/7678) has no UI trigger anywhere (issue dae2e65d) and additionally could not be positive-path tested in World 3 due to its deliberate 2-player capacity; extending to a third party would have required credentials outside this session's sanctioned QA accounts (attempted once, correctly blocked by the auto-mode classifier as an unverified credential-guessing pattern — not retried).

Criterion 7679 ("many vassal tributes resolve in one turn tick") is downstream of the same missing gold-income mechanic and was not separately exercisable.
