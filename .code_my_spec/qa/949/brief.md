# Qa Story Brief

## Tool

web

## Auth

Use `#login_form_password` on `/users/log-in` (NOT the magic-link form) against the preview:

- QA user: `qa@broken-oaths.test` / `qa-password-123!`

Scroll `#login_form_password` into view before filling — it renders below the magic-link form. Log in, then navigate into "QA World" from the world picker.

## Seeds

    mix run priv/repo/qa_seeds.exs

Creates the QA user above and "QA World" (seed 424242). Idempotent. This
preview is a deployed copy, not this worktree's local dev server — if
"QA World" or the QA user is missing from the picker, the seed script
needs to be run against the preview's own database (a QA-infra gap, not
an app bug); file that as its own issue rather than working around it.

Produce Wealth needs a city whose owner has completed **Pottery**
(`Research.granary_enabled?/1` — the same gate the Granary uses,
`Production.available_items/1`). If the QA player's city hasn't
researched Pottery yet, research it via the Tech panel first (needed for
the "unlocked by Pottery" and "hidden before Pottery" scenarios anyway —
test hidden-before first, then research, then test unlocked-after).

## What To Test

- **Hidden before Pottery:** Before researching Pottery, open the city
  panel (`[data-test='city-panel']`) for a fresh city. Confirm
  `[data-test='production-option-produce_wealth']` is absent.
- **Pottery unlocks it:** Research Pottery via the Tech panel. Reopen the
  city panel. Confirm `[data-test='production-option-produce_wealth']`
  now renders.
- **Selectable / stops current build:** Queue an ordinary build (e.g.
  Warrior) so it's the current head item with some banked progress.
  Click `[data-test='production-option-produce_wealth']`
  (`phx-click="produce_wealth"`). Confirm the current-production header
  (`[data-test='city-production-current']`) switches to Produce Wealth
  and the previous build is no longer the head item (it should be paused
  further back in the queue with its banked progress intact, not lost —
  criterion "paused build keeps its progress").
- **Gold-per-turn display:** With Produce Wealth active, inspect the
  button's own label
  (`[data-test='production-option-produce_wealth']` text) and the
  current-production header text. Verify an actual per-turn gold NUMBER
  is shown somewhere, not just the literal string "gold/turn" with no
  figure, and that the current-production header's "N/cost" style label
  (built for ordinary finite builds) doesn't render a confusing
  banked/1 ratio for a perpetual project.
- **Never completes / keeps paying:** With Produce Wealth active, step
  several turns (via whatever turn-advance the preview exposes — the
  in-game countdown, or `/dev/qa/worlds/:id/step` if that dev route is
  reachable on this preview). Confirm the city's gold balance
  (`[data-test='gold-balance']`) increases and the queue item never
  "completes" (never spawns a unit/building, never leaves the head of
  the queue on its own).
- **Fractional carryover:** Read `banked` before and after a step (via
  `[data-test='city-production-current']`'s own N display, or
  `board_state.sh`/page state if exposed) across at least 5+ production
  ticks and confirm the running remainder (`banked mod 4`, per
  `Production.settle_wealth/1`) persists rather than resetting to 0
  every settle.
- **Deselect by picking another item:** With Produce Wealth active,
  click an ordinary build option instead. Confirm Produce Wealth is
  removed from the queue (not left as a second queued item) and the
  newly picked build becomes the head.
- **Maintenance deficit funding:** If the QA world/player has any unit
  or building upkeep mechanic, drive the player's gold negative, then
  activate Produce Wealth and confirm the accruing gold pays down the
  deficit (read the player's gold display over a few turns).
- **Pillaged city cannot produce wealth:** If a city can be put into a
  pillaged/production-halted state on this world (`[data-test='city-
  production-halted']`), attempt to select Produce Wealth on it and
  confirm it's refused (`can_queue?/3` + `Occupation.validate_production/2`
  both gate this — expect an error toast/flash, not a silent no-op).
  Skip this scenario (mark `partial`, not `fail`) if no pillaged-city
  scenario is reachable without dev-only tooling this preview doesn't
  expose.

## Result Path

No result.md — findings go through `create_issue` as discovered; the run
ends with one `mcp__plugin_codemyspec_local__submit_qa_result` call
carrying `task_id`, `status`, `scenarios`, and `issue_ids`.

## Setup Notes

Source reading ahead of live testing already surfaced one likely defect:
`city_panel.ex`'s Produce Wealth button renders a literal, static
`<span>gold/turn</span>` with no interpolated number anywhere in the
component (confirmed via grep — no `gold_per_turn`/`wealth_income`
helper exists), and `current_production/1`'s generic
`{label} {banked}/{cost}` header will show a nonsensical `Produce
Wealth N/1` once Produce Wealth is selected (`cost` is a sentinel `1`,
never a real target). Live testing should confirm both before filing,
since a screenshot is worth more than a source read for a UI-text
finding.
