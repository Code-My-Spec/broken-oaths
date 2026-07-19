# Qa Story Brief — 911 Strategic Resources: Copper for Bronze Spearmen

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) + dev QA control surface
(`/dev/qa/worlds/3/step` to accrue science).

## Auth

- Player A: `qa-901-a@broken-oaths.test` / `qa-password-123!` — player_id 11
- Player B: `qa-901-b@broken-oaths.test` / `qa-password-123!` — player_id 12

## Seeds

World 3, neither player has researched anything at session start. Bronze Working requires Mining
first (75 + 100 science, ~13 turns each at 8-10 sci/turn) — select via the real Tech panel
(`tech-mining`, then `tech-bronze_working` + the confirm modal), step turns to accrue science.

## What To Test

- BEFORE Bronze Working: open a city's Build catalog and confirm NO Bronze Spearman row exists at
  all (only Settler/Worker/Warrior) — implicit legibility check, tech-gated absence.
- Research Mining then Bronze Working for real via the Tech panel. Confirm the modal warning
  ("This will advance you to Bronze Age. Continue?") and that `game_player_research.completed_techs`
  gains `bronze_working` on confirm.
- AFTER Bronze Working: re-open the Build catalog and confirm the Bronze Spearman row NOW appears,
  with `data-test="production-requirement-bronze_spearman"` reading "Requires Copper" — legibility
  confirmed (7708).
- Check the city's territory tiles for a Copper resource (`Worlds.Resources.at/2`, deterministic
  per-seed) — if present, click the Bronze Spearman build button and confirm it's enabled/queues
  (7704), and confirm it's counted even if the Copper tile itself is unworked (7706). If absent,
  confirm the build button instead renders `disabled`/`data-disabled="true"` (7705).

## Result Path

Findings filed via `create_issue`, verdict via `submit_qa_result` (task_id
`016f017b-4169-4ec5-a7ec-bb253c8a7adb`). Screenshots at `.code_my_spec/qa/911/screenshots/`.

## Setup Notes

World 3's terrain (seed 901901, frequency 8) was searched across ~18 known Hills tiles (both
players' fog windows combined) and NO Copper deposit was found within either existing city's
territory nor among any currently-explored Hills tile. This blocks the POSITIVE access path
(7704, 7706) — a genuine world-generation/exploration coverage gap for this specific seed, not a
code defect. The NEGATIVE path (no access → disabled, with the "Requires Copper" reason legible)
is fully verified live.
