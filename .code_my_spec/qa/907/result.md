# Qa Result — 907 Automatic Vassalization (RE-QA #2)

## Status: pass

## Summary

The blocking gap from the prior two sessions (907 fully depends on 906's capture-completion UI,
issue 34d30fca) is closed now that 906's Move In button genuinely works. This session captured
completely FRESH, live, end-to-end evidence — not reconstruction: player B's real button click
against player A's broken city fired the last-free-city check server-side in real time, created
a brand-new `Vassalage` row, and the "Terms of Oath" modal rendered unprompted the moment player
A's browser next loaded `/play/3`. Every mechanic this story owns (trigger, Oath screen with all
4 agendas, default row fields, both players' UI surfacing, vassal-keeps-playing) is confirmed
working through real clicks.

## Scenarios

- **7666 Losing the last free city triggers vassalization** — PASS, fully live. Capturing city 8
  (906's Move In click) immediately produced a new `game_vassalages` row (id 3: lord=12,
  vassal=11) with no manual seeding — the trigger fired in real time off a genuine client action.
- **7667 Losing one of several cities does not create vassalage** — not testable; World 3 is a
  2-player/1-city-each world by construction, unchanged structural gap.
- **7668 Vassal secretly chooses a Hidden Agenda on the Oath screen** — PASS, fully live. The
  "Terms of Oath" modal rendered unprompted for player A on page load with all 4 options; clicked
  "Restore" for real, `game_vassalages.hidden_agenda` persisted as `restore`, modal closed.
- **7669 New vassalage record created with default forward-looking fields** — PASS. psql showed
  `tribute_rate: 0.25, oath_strain: 0, contract_terms: {}, status: active, hidden_agenda: NULL`
  on creation, before the Oath screen click.
- **7670 Both players notified and the relationship surfaces in each UI** — PASS. Player A (new
  vassal) top bar showed "Sworn to qa-901-b@broken-oaths.test" + 25% rate badge; player B (new
  lord) "Vassals (1)" dropdown showed player A's row with rate/oath-strain, plus a "Steward:
  Collect Bank" affordance once player A went offline (910 overlap). Live PubSub push not
  independently instrumented, but the resulting UI state on both sides is correct and immediate.
- **7671 Vassal keeps playing normally after subjugation** — PASS. Player A retained full command
  of their units and continued playing (research, movement) after subjugation.
- **7672 A player already holding an occupied city becomes a vassal when their last free city
  falls** — not testable; requires 2+ cities per player, same gap as prior sessions.

## Evidence

Screenshots at `.code_my_spec/qa/907/screenshots/` (this session prefixed `re2_`):
- `re2_01_playerB_now_lord_of_playerA.png` — player B's fresh "Vassals (1)" panel showing player
  A, 25% default rate, 0 oath strain, immediately after the capture
- `re2_02_playerA_oath_screen.png` — the "Terms of Oath" modal rendering UNPROMPTED for player A
  on page load, with the top bar simultaneously showing both "Vassals (1)" (their own, pre-existing
  lordship over player B) and "Captured (1)" (their new holding)

psql verification: `game_vassalages` (two independent rows: id 2 lord=11/vassal=12 unaffected by
this session's events; id 3 lord=12/vassal=11 freshly created with default fields, then
`hidden_agenda=restore` after the click).

## Issues Filed

None new. The previously-filed issue 34d30fca (vassalization unreachable, gated behind 906) is
confirmed resolved by this session's live evidence.
