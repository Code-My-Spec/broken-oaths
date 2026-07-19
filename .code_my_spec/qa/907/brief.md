# Qa Story Brief — 907 Automatic Vassalization (RE-QA #2)

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev).

## Auth

- Player A (fresh vassal this session): `qa-901-a@broken-oaths.test` / `qa-password-123!` — player_id 11
- Player B (fresh lord this session): `qa-901-b@broken-oaths.test` / `qa-password-123!` — player_id 12

## Seeds

World 3. Builds directly on 906's RE-QA #2 session: player B's warrior captured player A's only
city (city 8) via the real "Move In" button, leaving player A with zero free cities.

## What To Test

- Immediately after 906's capture click, log in as player A (`qa-901-a`) fresh (no prior session
  cookie) and confirm the "Terms of Oath" modal (`data-test="oath-screen"`) renders UNPROMPTED on
  page load — this is the live trigger firing in real time, not a seeded/reconstructed row.
- Confirm all 4 agenda options render (`agenda-option-restore/usurp/kingmaker/merchant_prince`)
  and click one for real; verify `game_vassalages.hidden_agenda` persists via psql.
- Confirm the top bar simultaneously shows "Vassals (1)" and "Captured (1)" for player A (since
  they were ALSO already a lord of player B from the original vassalage, and now additionally
  hold a captured city) — i.e. both relationships render correctly without UI confusion.
- Log in as player B and confirm their own Vassals panel now lists player A with default fields
  (25% rate, 0 oath strain) — psql-verify the fresh `Vassalage` row's defaults directly.

## Result Path

Findings filed via `create_issue`, verdict via `submit_qa_result` (task_id
`ba9a7709-8589-4ef8-b954-5851098ab733`). Screenshots at `.code_my_spec/qa/907/screenshots/`
(prefixed `re2_`).

## Setup Notes

World 3's 2-player cap still blocks criteria 7667/7672 (needs a player with 2+ cities) — noted as
a persistent, genuine environment gap. The reciprocal vassalage this session produced (on top of
the pre-existing lord=11/vassal=12 relationship) is a novel, useful stress case: both directions
render correctly and independently in the UI with no observed crash or data corruption.
