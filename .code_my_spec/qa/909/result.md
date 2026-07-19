# Qa Result — 909 Gold Bank and Upgrades

## Status: pass

## Summary

All six criteria verified with clean, isolated, live evidence through real gameplay and real
button clicks — the online/offline split, the cap, Collect, and Upgrade (both the success and
the blocked-insufficient-funds path) all behave exactly per spec.

## Scenarios

- **7680 Offline earnings accrue into the bank below the cap** — PASS. With player 12
  disconnected, 12 stepped turns raised their `banked_gold` from 12 to 48 (+3/turn = exactly
  `base_gold(4)=1+floor(4/2)=3`, no coast bonus), while `gold` only moved via tribute — clean,
  isolated accrual.
- **7681 Bank holds at the cap and wastes the overflow** — PASS. Left offline for enough turns at
  a high tribute-drain rate, player 12's `banked_gold` sat exactly at `bank_cap` (100/100),
  neither exceeding it nor losing already-banked gold.
- **7682 Logged-in earnings land in the treasury, not the bank** — PASS. While player 12 stayed
  connected for 12 real stepped turns, `banked_gold` remained EXACTLY unchanged (66→66) the entire
  time while `gold` rose every turn — definitive isolation of the online path.
- **7683 Collect sweeps the banked gold into the treasury** — PASS. Real `collect-bank` click for
  player 11: `gold` 259→346 (+87, matching the swept `banked_gold`), `banked_gold` reset to 0.
- **7684 Upgrading the bank raises the cap** — PASS. Real `upgrade-bank` click with 706 gold on
  hand (cost 500 for a 100→200 cap raise): `gold` 706→206 (-500 exactly), `bank_cap` 100→200
  (+100 exactly) — both deltas matched `Bank.upgrade_cost/1`/`upgraded_cap/1` precisely.
- **7685 Upgrade is blocked when the player cannot afford it** — PASS. Real `upgrade-bank` click
  with only 346 gold (cost 500): `data-test="bank-error"` rendered "You can't afford that upgrade
  yet.", `gold` and `bank_cap` both unchanged — no partial charge.

## Evidence

Screenshots at `.code_my_spec/qa/909/screenshots/`:
- `re2_01_playerA_bank_after_upgrade.png` — top bar showing "0 / 200" bank badge immediately
  after the real Upgrade click

psql verification throughout: `game_players.gold`/`banked_gold`/`bank_cap` for both players
across dozens of stepped turns, isolating the online-vs-offline accrual paths and the exact
Collect/Upgrade deltas.

## Issues Filed

None.
