# Qa Result — 908 Tribute Payments (RE-QA)

## Status: partial

## Summary

**The core previously-broken piece — real gold income actually feeding tribute — is
DEFINITIVELY FIXED and verified with clean, unambiguous, non-zero evidence.** The prior QA
session's failure mode was EXACTLY zero gold movement across 3 real stepped boundaries at a
40% rate; this session, after clearing world 3's leftover gold-log/vassalage state and
recreating a fresh vassalage, stepping turns produced real `game_gold_logs` rows and matching
`game_players.gold` deltas every single boundary, with the math checking out exactly
(`round(income × rate)`, income = `base_gold(size) = 1 + floor(size/2)` per story 912).

Tribute rate UI (both lord-set and vassal-visible), the raised-rate-applies-next-boundary
behavior, and debt (negative balance) were all verified with real UI actions and real turn
processing. Levy Answer/Refuse UI is real and works; the Issue form is correctly, intentionally
absent given World 3's 2-player cap (verified as CORRECT behavior per the code's own documented
intent, not a bug). One genuine gap found: refusing a call to arms spikes Oath Strain but never
dings Honor, despite criterion 7678's wording (filed as issue c0ec53ed — this is a documented,
known gap per `Tribute`'s own moduledoc, not a surprise regression).

Like 906/907, this story's own mechanics are solid once a vassalage exists — the only thing
keeping this at "partial" rather than "pass" is the same upstream dependency: a real player
cannot yet create that vassalage through the shipped UI (906's capture-completion gap, issue
7f91cff2).

## Scenarios

- **7673 Lord raises a vassal's tribute rate from the Vassals panel** — PASS, fully live. Real
  form submit raised the rate 25% → 40% (and later, for evidence clarity, → 100%); `psql`
  confirmed persistence each time; player B's own `my-tribute-rate` badge updated to match on
  next render, both times.
- **7674 Vassal earning income at a set rate pays the correct tribute** — PASS (formula
  verified with this world's real numbers, not the story's literal "12g/25%/3g" example): city
  9's real per-turn income was 3 gold (`base_gold(4) = 1 + floor(4/2) = 3`, no coast tiles
  worked); at 25% tribute was 1 gold (`round(3 × 0.25) = 1`), matching exactly, turn after
  turn, in real `game_gold_logs` rows.
- **7675 A raised rate is applied on the next turn's tribute** — PASS, clean before/after.
  Raised the rate 40% → 100% then stepped once: tribute jumped from 1 gold/turn to 3
  gold/turn on the VERY NEXT boundary (`round(3 × 1.0) = 3`), unambiguous evidence the fresh
  rate is read live each boundary (`active_vassalages/1` queries the DB fresh every tick, no
  in-memory staleness for this field).
- **7676 Vassal with an empty treasury goes into debt paying tribute** — PASS. Stepped enough
  turns at the 100% rate for the vassal's un-boosted `gold` balance (their own income was
  banked, not added to `gold`, while their session was disconnected) to run through
  repeated tribute deductions into NEGATIVE territory: `game_players.gold = -1`, confirmed both
  via psql and the vassal's own top-bar gold badge rendering "-1". Full tribute amount (3
  gold) was still logged every turn, never clamped or partial.
- **7677 Vassal answers a call to arms and keeps command of the units sent** — PASS. Since a
  genuine 3-party Issue is architecturally blocked in World 3 (2-region cap means the lord's
  only known player IS the vassal — `levy_targets/2` correctly excludes them, and the
  `issue-levy-form` is correctly ABSENT, verified in `02_vassals_panel_lord_view.png`), the
  vassal-side Answer control was verified against a manufactured-but-schema-valid pending
  `game_levies` row (real FK to an existing `game_players` row elsewhere in the DB, purely to
  satisfy the NOT NULL/FK constraint — not a claim that a real 3-party call was issued). Real
  `answer-levy` click: `game_levies.status` → `answered`, and all 3 of the vassal's units
  (lord, 2 warriors) remained exactly as before — none deleted or reassigned.
- **7678 Vassal refuses the call to arms and takes strain and Honor hits** — PARTIAL. Same
  manufactured-row caveat as 7677. Real `refuse-levy` click: `game_levies.status` → `refused`,
  `game_vassalages.oath_strain` 0 → 15 (exactly `Tribute.oath_strain_refusal_spike/0`). Honor
  was NOT docked (100 → 100, unchanged) — see issue c0ec53ed.
- **7679 Many vassal tributes resolve in one turn tick** — not independently tested; World 3
  has only one active vassalage. `Tribute.collect_all/5`'s pure fan-out logic is unit-tested
  elsewhere (`tribute_test.exs`); the single-vassalage case is thoroughly live-verified above.

## Evidence

Screenshots at `.code_my_spec/qa/908/screenshots/`:
- `02_rate_40_confirmed_lord.png`, `03_vassal_badge_40pct.png` — real rate-change UI, both sides
- `04_vassal_negative_gold.png` — debt state ("-1" gold badge) live in the UI
- `05_levy_pending_answer_refuse_buttons.png`, `06_after_refuse_click.png`, `07_after_answer_click.png` — real levy Answer/Refuse UI and resulting badges

psql verification: `game_gold_logs` (6 real tribute rows across the session, non-zero, correct
amounts each boundary), `game_players.gold` (deltas matching the logged amounts exactly),
`game_vassalages.tribute_rate/oath_strain`, `game_levies.status`.

## Issues Filed

- c0ec53ed (medium, app) — refusing a levy never dings Honor despite criterion 7678's wording (known gap per code's own docs)

Not re-filed (already tracked against 906): the World-3 2-region capacity cap blocking a
genuine 3-party Issue click — unchanged environmental constraint from the original QA session,
not a new finding.
