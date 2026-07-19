# Qa Story Brief — 907 Automatic Vassalization

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) for state verification.

## Auth

Same two accounts as 906, password `qa-password-123!`:

- Player A (captor/lord): `qa-901-a@broken-oaths.test` — player_id 11
- Player B (defeated/vassal): `qa-901-b@broken-oaths.test` — player_id 12

## Seeds

Depends on 906's capture actually landing first (World 3, city 9 captured by player 11 — see 906's brief/results). Since each World 3 player has exactly one city, any successful capture of city 9 is automatically a last-free-city capture, which is the direct trigger for this story.

## What To Test

- After city 9 (player 12's only city) is captured (occupied_by_player_id = 11), verify via `psql` that a `game_vassalages` row was created with `lord_player_id=11, vassal_player_id=12, tribute_rate=0.25 (default), oath_strain=0, hidden_agenda=null, contract_terms={}, status=active` — criteria 7666, 7669.
- Log in as player A: verify the "Vassals (1)" dropdown appears in the top bar and expand it — verify the vassal row shows email, tribute rate, and Oath Strain — criterion 7670 (lord's own UI).
- Log in as player B: verify the top bar shows a "Sworn to qa-901-a@broken-oaths.test" badge plus the current tribute rate badge — criterion 7670 (vassal's own UI).
- Verify the "Terms of Oath" modal renders for player B with all four Hidden Agenda options (Restore, Usurp, Kingmaker, Merchant Prince) — criterion 7668.
- Click one agenda option (`data-test="agenda-option-restore"`) and verify via psql that `game_vassalages.hidden_agenda` persists and the modal closes.
- Verify player B can still select/move their remaining units (lord 214, warrior 377) and still owns/can queue production in their own occupied city (id 9) — criterion 7671.
- Verify city 9 still appears in player B's own `cities` list (read via the Board hook) even though occupied, and its CityPanel shows an "occupied" status badge and normal Build catalog — criterion 7663 (shared with 906) supporting 7671.

## Result Path

Findings filed as issues via `create_issue`, final verdict submitted via `submit_qa_result` (task_id 4e84a79e-aa95-46d6-9b3b-b4d35e00236d). Screenshots at `.code_my_spec/qa/907/screenshots/`.

## Setup Notes

Criteria 7667 ("losing one of several cities does not create vassalage") and 7672 ("a player already holding an occupied city becomes a vassal when their last free city falls") both require a player with 2+ cities and a second attacking account — infeasible in World 3 (2 players, 1 city each by construction) and outside this session's sanctioned credentials for a larger world. Not exercised live; `Vassalization.vassalization_events/2`'s filter (`Siege.no_free_cities?/2`, which requires ALL of a player's cities to be occupied) was reviewed by code inspection only for these two criteria.

This story's own mechanics (trigger, oath screen, hidden agenda persistence, notifications, vassal-keeps-playing) are otherwise entirely reachable via genuine LiveView events once a capture exists — no missing-button workaround was needed for anything in 907 itself. The blocker is upstream, in 906's missing attack/capture UI (see that story's filed issues) — a real player can never reach this state through the shipped board.
