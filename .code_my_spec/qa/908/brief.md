# Qa Story Brief — 908 Tribute Payments (RE-QA #2)

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) + dev QA control surface
(`/dev/qa/worlds/3/step`).

## Auth

- Player A (lord in relationship id=2, vassal in fresh relationship id=3): `qa-901-a@broken-oaths.test` — player_id 11
- Player B (vassal in relationship id=2, lord in fresh relationship id=3): `qa-901-b@broken-oaths.test` — player_id 12

## Seeds

World 3 now carries TWO simultaneous, independent active vassalages after 906/907's RE-QA #2
session: id=2 (lord=11, vassal=12, pre-existing) and id=3 (lord=12, vassal=11, freshly created by
906's capture). Both resolve tribute every turn boundary — genuine live coverage of "many vassal
tributes resolve in one turn tick" without needing a 3rd account.

## What To Test

- As player A, raise relationship id=2's rate via the real `set_tribute_rate` form (`vassal-row-12`)
  and confirm persistence + the next-boundary tribute amount changes accordingly (7673, 7675).
- Step turns and confirm BOTH vassalages produce `game_gold_logs` rows in the SAME tick
  (`from_player_id=12,to=11` AND `from_player_id=11,to=12`), each `round(income × rate)` — 7674,
  7679 (many vassalages resolving concurrently, now genuinely two, not one).
- Crank rate to 100% and step many turns to drive one side into debt — confirm negative
  `game_players.gold`, full (non-clamped) tribute still logged — 7676.
- Answer/Refuse levy UI — reuse the manufactured-but-schema-valid pending row approach from the
  prior session (World 3's 2-player cap still blocks a genuine 3-party Issue).

## Result Path

Findings filed via `create_issue`, verdict via `submit_qa_result` (task_id
`6f4dae99-0f93-4995-9d8d-da6a9035f8a8`). Screenshots at `.code_my_spec/qa/908/screenshots/`
(prefixed `re2_`).

## Setup Notes

Call-to-arms' full positive path (issue against a genuine 3rd party) remains architecturally
blocked by World 3's 2-player cap — unchanged, noted gap, not worked around.
