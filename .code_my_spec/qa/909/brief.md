# Qa Story Brief — 909 Gold Bank and Upgrades

## Tool

web (Vibium CLI, sandbox disabled) + psql (broken_oaths_dev) + dev QA control surface
(`/dev/qa/worlds/3/step`).

## Auth

- Player A: `qa-901-a@broken-oaths.test` / `qa-password-123!` — player_id 11
- Player B: `qa-901-b@broken-oaths.test` / `qa-password-123!` — player_id 12

## Seeds

World 3, both players already own a city with real per-turn gold income (912). "Offline" in this
world simply means the player's browser session isn't connected — `Presence.connect/2` fires on
LiveView mount, so logging out (or never logging in) makes a player read as offline for
`Bank.settle_income/3`'s purposes.

## What To Test

- With one player logged OUT (offline) and the other logged IN (online), step several turns and
  confirm via psql: the OFFLINE player's `banked_gold` rises by their city income each turn while
  `gold` stays flat (except for tribute, which always moves `gold` directly regardless of online
  status) — 7680. The ONLINE player's `banked_gold` stays completely static while `gold` rises —
  7682.
- Step enough turns to fill an offline player's bank to `bank_cap` and confirm it holds exactly at
  the cap with no further growth (no loss, just waste) — 7681.
- Log in as the offline player, click `data-test="collect-bank"` — confirm `banked_gold` sweeps
  entirely into `gold` and resets to 0 — 7683.
- Click `data-test="upgrade-bank"` with insufficient gold — confirm a `bank-error` message and NO
  state change (no partial charge) — 7685. Accumulate gold (via a temporarily-cranked tribute
  rate + stepped turns, or just banked play) past the cost, click again — confirm `bank_cap` rises
  by exactly `Bank.upgrade_cost/1`'s increment and `gold` drops by exactly the cost — 7684.

## Result Path

Findings filed via `create_issue`, verdict via `submit_qa_result` (task_id
`0527ecc9-eb48-4d66-80ea-5c3384ce6123`). Screenshots at `.code_my_spec/qa/909/screenshots/`.

## Setup Notes

None — this story's mechanics are fully reachable with the existing 2-player World 3 setup, no
capacity gap.
