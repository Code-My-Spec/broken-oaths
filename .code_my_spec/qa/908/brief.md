# Qa Story Brief — 908 Tribute Payments (RE-QA)

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) for state verification + dev QA control surface (`/dev/qa/worlds/3/step`) to advance deterministic turns.

## Auth

Same two accounts as 906/907, password `qa-password-123!`:

- Player A (lord): `qa-901-a@broken-oaths.test` — player_id 11
- Player B (vassal): `qa-901-b@broken-oaths.test` — player_id 12

## Seeds

Depends on the fresh active Vassalage row created in 907 (World 3, id 2, lord=11, vassal=12, tribute_rate=0.25). World 3 stays paused between assertions; `POST /dev/qa/worlds/3/step` advances exactly one turn on demand (production accrual, tribute, bank settlement) without waiting the real clock.

## What To Test

- Log in as player A, open the Vassals dropdown (`data-test="vassals-list"`), submit the `set_tribute_rate` form on the vassal row (`data-test="vassal-row-12"`) to raise the rate from 25% to 40% — verify via psql (`game_vassalages.tribute_rate = 0.4`) it persists, and player B's own `data-test="my-tribute-rate"` badge reflects `40%` on next render — criterion 7673.
- Record baseline `game_players.gold` for both players and `game_gold_logs` row count for world 3 (both 0 after this session's cleanup — see Setup Notes).
- Advance the world with `POST /dev/qa/worlds/3/step` at least 3 times (confirm via `GET /dev/qa/worlds/3` that `turn` actually advances).
- **The core regression under re-QA**: after each step, re-check `game_players.gold` for both players and `game_gold_logs` — story 912 wired REAL per-turn city gold income (`Yields.city_gold_income/2`: `1 + floor(size/2)` base + 1 per worked Coast tile) into `apply_tribute/1`'s `income_by_player` map, replacing the old always-empty test-only seam. Expect NON-ZERO tribute: `game_gold_logs` gains a `from_player_id=12, to_player_id=11, reason=tribute` row each boundary, and player 12's gold visibly drops while player 11's rises by the same amount — criteria 7674 (income × rate), 7675 (raised rate applied on the very next boundary, since we raised it BEFORE stepping).
- Debt scenario (criterion 7676): before stepping, drive player 12's `game_players.gold` down near/at 0 via psql (documented scenario construction — no dev-QA HTTP surface exists for player gold, only units/camps) then step once more; confirm gold goes NEGATIVE (not clamped at 0, not a partial payment) and a full-amount `game_gold_logs` row is still written.
- Issue Call to Arms: log in as player A, expand the vassal row — confirm the `issue-levy-form-12` is CORRECTLY ABSENT (by design: `levy_targets/2` excludes the vassal from `@known_players`, and World 3's 2-player/2-region cap means the lord's only known player IS the vassal — no legal 3rd-party target exists). This is a genuine, positive verification of the code's own documented intent ("an empty `<select>` would only ever be refused server-side anyway"), not a bug.
- Because a real 3-party Issue click is architecturally unreachable in World 3, the vassal-side Answer/Refuse UI (criteria 7677/7678) is verified against a manufactured-but-schema-valid `game_levies` row (`status=pending`, `target_player_id` set to a valid `game_players.id` from elsewhere in the DB purely to satisfy the FK — NOT a claim that a real 3-party call was issued) inserted via psql, then driven with REAL clicks:
  - `data-test="refuse-levy"` on player B's status badge — confirm `game_levies.status` → `refused`, and `game_vassalages.oath_strain` rises by 15 (`Tribute.oath_strain_refusal_spike/0`) — criterion 7678. Note: per `Tribute`'s own moduledoc ("Honor itself has no ledger anywhere yet in this batch"), NO `game_players.honor` change is expected on refusal despite the story text saying "Honor hits" — flag this as a doc/implementation gap if honor is unchanged, not a UI bug.
  - A second manufactured `pending` row, `data-test="answer-levy"` — confirm `game_levies.status` → `answered` and NO units are deleted/reassigned (vassal keeps command) — criterion 7677.
- Criterion 7679 ("many vassal tributes resolve in one turn tick") is only meaningfully distinct with 2+ concurrent vassalages in one world — same single-vassalage limitation as before; `collect_all/5`'s pure-function fan-out is unit-tested elsewhere (`tribute_test.exs`) and not re-verified live here beyond the single-vassalage case already covered above.

## Result Path

Findings filed as issues via `create_issue`, final verdict submitted via `submit_qa_result` (task_id ba8bcf56-8c00-44ea-9dcb-7b088c22ac13). Screenshots at `.code_my_spec/qa/908/screenshots/`.

## Setup Notes

This session cleared world 3's leftover `game_gold_logs` (none existed) and `game_vassalages` from the prior (pre-fix) QA session, then recreated a fresh vassalage row (see 907's brief) — so gold-log baselines are genuinely zero going into this test, making a nonzero delta unambiguous evidence the story-912 income fix landed (the prior session's failure mode was exactly zero movement across 3 real stepped boundaries at a 40% rate with an active vassalage).

Call-to-arms' full positive path (issue against a genuine 3rd party) remains architecturally blocked by World 3's 2-region/2-player cap — an environment capacity constraint, not a missing feature, unchanged from the original QA session. Extending to a 3rd real account was judged out of scope per this session's instructions (avoid inventing workarounds for credential/capacity gaps — note them instead).
