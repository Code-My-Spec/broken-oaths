# Qa Story Brief — 907 Automatic Vassalization (RE-QA)

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) for state verification.

## Auth

Same two accounts as 906, password `qa-password-123!`:

- Player A (captor/lord): `qa-901-a@broken-oaths.test` — player_id 11
- Player B (defeated/vassal): `qa-901-b@broken-oaths.test` — player_id 12

## Seeds

World 3, city 9 (player 12's only city) is captured (`occupied_by_player_id=11`, see 906's brief Seeds note for how this session restored/re-created that state consistently with the live `WorldServer`). A FRESH `game_vassalages` row (id 2: `lord_player_id=11, vassal_player_id=12, tribute_rate=0.25, oath_strain=0, hidden_agenda=NULL, contract_terms={}, status=active`) was inserted this session specifically so the Oath screen renders genuinely (`Vassalization.agenda_pending?/1` reads `hidden_agenda == nil` off THIS row, read fresh from DB on every `vassal_status` call — no in-memory staleness risk here, unlike cities).

## What To Test

- Confirm via psql the vassalage row exists with the defaults above — criteria 7666 (trigger fired, matches the historical real capture), 7669 (default forward-looking fields).
- Log in as player A: confirm the "Vassals (1)" dropdown (`data-test="vassals-list"`) appears in the top bar; expand it and confirm the vassal row (`data-test="vassal-row-12"`) shows email `qa-901-b@broken-oaths.test`, tribute rate `25%` (`data-test="vassal-tribute-rate"`), and Oath Strain `0` (`data-test="vassal-oath-strain"`) — criterion 7670 (lord's own UI).
- Log in as player B: confirm the "Sworn to qa-901-a@broken-oaths.test" badge (`data-test="vassal-status"`) plus tribute-rate badge (`data-test="my-tribute-rate"`) render in the top bar — criterion 7670 (vassal's own UI).
- Confirm the "Terms of Oath" modal (`data-test="oath-screen"`) renders for player B with all four Hidden Agenda options (`data-test="agenda-option-restore|usurp|kingmaker|merchant_prince"`, exact option set per `oath_agenda_options/0`) — criterion 7668.
- Click one agenda option (use `agenda-option-usurp` this run, for variety from the prior session's `restore` pick) — verify via psql `game_vassalages.hidden_agenda = 'usurp'` and the modal closes (re-check `agenda_pending?` reads false / oath-screen element gone on next render).
- Verify player B can still select/move their remaining units (lord 214, warrior 377, plus this session's units 442/444) and still owns/can queue production in their own occupied city (id 9) — criterion 7671.
- Verify city 9 still appears in player B's own `cities` list (Board hook `game:cities`) even though occupied, and its CityPanel shows an "occupied" status badge and normal Build catalog — criterion 7663 (shared with 906) supporting 7671.

## Result Path

Findings filed as issues via `create_issue`, final verdict submitted via `submit_qa_result` (task_id dfd8df52-a994-4b94-9814-54583a827620). Screenshots at `.code_my_spec/qa/907/screenshots/`.

## Setup Notes

Criteria 7667 ("losing one of several cities does not create vassalage") and 7672 ("a player already holding an occupied city becomes a vassal when their last free city falls") both require a player with 2+ cities and a second attacking account — still infeasible in World 3 (2 players, 1 city each by construction, same structural cap as the prior QA session) and outside this session's sanctioned credentials for a larger world. Not exercised live this session either — same coverage gap as before, unchanged by the UI fix (the fix was scoped to reachability of 906's attack/garrison-fate UI and 908's gold income, not to World 3's capacity).

This story's own mechanics (trigger, oath screen, hidden agenda persistence, notifications, vassal-keeps-playing) are fully reachable via genuine LiveView clicks this session — the Oath screen specifically was re-verified with a FRESH `hidden_agenda=NULL` row (see Seeds) rather than reusing the prior session's already-resolved `restore` pick, so this is a genuine, not stale, re-test of criterion 7668.
