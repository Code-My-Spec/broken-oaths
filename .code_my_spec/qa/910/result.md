# Qa Result — 910 Feudal Stewardship (re-QA, round 3)

## Status: pass

## Summary

The two gaps identified in the prior `partial` (no click-through UI for production
stewardship or emergency defense) are now closed and verified LIVE end-to-end. Using
World 3's existing lord/vassal + ally relationship between players 11 and 12 (player 11
online, player 12 taken offline for this session), the new "City 1 / [item ▾] / Steward:
Set Production" form and the "Under attack! / Defend → Tile N" buttons in the Vassals
panel both worked exactly as designed:

- Production stewardship queued a real `worker` item onto player 12's OFFLINE city 9
  (`game_production_items` row inserted, position 1) and wrote a `production_set`
  `game_steward_logs` row.
- Emergency defense: player 12's warrior (unit 444) was damaged via the dev QA surface
  (hp 50/100) to trigger `Stewardship.under_attack?/1`; the Vassals panel correctly
  surfaced "Under attack!" with six `Defend → Tile <adjacent>` buttons (504, 512, 513,
  508, 636, 632 — exactly the unit's real adjacent tiles); clicking one moved the unit
  from tile 505 → 504 and wrote an `emergency_defense` `game_steward_logs` row.
- Healed the same unit back to 100/100 HP and reloaded: the entire "Under attack!" /
  defend section disappeared from the Vassals panel — no defend UI exists at all once
  the owner isn't under attack (7692, live-confirmed).
- The steward-set production dropdown offered exactly `{Settler, Worker, Warrior,
  Bronze Spearman}` (Granary excluded — player 12 hasn't researched Pottery) — precisely
  `Production.available_items/1` filtered through `Stewardship.constructive_item?/1`.
  Every buildable type in this codebase is constructive by design (confirmed via code
  read of `Stewardship`'s `@constructive_items` list — it equals the full catalog), so
  there is no non-constructive item that could ever appear in the dropdown to omit; the
  whitelist filter is exercised (not dead code) even though it's a no-op today.
  Confirmed via `grep` that no `phx-click`/`phx-submit` binding exists anywhere in
  `play.ex` or `alliance_panel.ex` for `steward_disband_unit`, `steward_cancel_production_item`,
  `steward_attack`, or `steward_queue_move` — disbanding, cancel-griefing, marching the
  army off, and attacking remain unreachable from the real UI by construction (7691, 7694).
- Player 12's OWN steward-log panel (their own session, logged back in) correctly listed
  all 4 actions taken on their behalf by player 11 (`bank_collect` ×1 prior session,
  `production_set`, `emergency_defense`, plus one more `bank_collect`), scoped correctly
  to entries where THEY are the owner (7695, reconfirmed with the two new action types).

## Scenarios

- **7686 Lord and fellow vassal can steward an offline household member** — PASS. Real
  clicks via the Vassals panel (lord path) this session, on top of the previously-verified
  bank-collect evidence.
- **7687 A vassal cannot steward their own lord** — PASS (unchanged, structural/UI-absence,
  re-confirmed by code read — `vassals_panel` only ever renders the current user's OWN
  vassals).
- **7688 Allied peers can steward each other symmetrically** — PASS (bidirectional live
  evidence from the prior session; the `steward_role/4` code path is identical for
  production/defend as it is for bank-collect, and `alliance_panel.ex` carries the
  identical production-form + defend-button markup, confirmed by code read this session).
- **7689 Steward sweeps the offline bank entirely to the owner** — PASS (unchanged, live
  evidence from prior session).
- **7690 Steward queues a whitelisted constructive build** — PASS, live this session.
  `game_production_items` row `{id: 52, city_id: 9, type: worker, position: 1}` inserted
  via the real "Steward: Set Production" button click.
- **7691 Steward cannot disband a unit or cancel an in-progress build** — PASS, structural
  (no UI path exists for either — `grep` confirms zero `phx-click`/`phx-submit` bindings
  for `steward_disband_unit`/`steward_cancel_production_item` in either panel template).
- **7692 Steward cannot move units when the owner is not under attack** — PASS, live this
  session. Healed the target unit to full HP and reloaded the Vassals panel — the entire
  emergency-defense section (banner + buttons) is absent; there's no button to even
  attempt an illegal move.
- **7693 Ally issues a defensive order while the offline owner is under attack** — PASS,
  live this session via the lord/vassal channel (`Defend → Tile 504` click moved unit 444
  from tile 505 to 504, logged). The ally channel's identical code path was live-exercised
  for bank-collect in the prior session; `alliance_panel.ex`'s defend markup is byte-identical
  in structure to `play.ex`'s vassal-row version (confirmed by code read).
- **7694 Steward cannot use the emergency window to march the army off or attack** — PASS,
  structural (no `steward_attack`/`steward_queue_move` UI binding exists in either panel;
  every defend button offered targets a `Stewardship.defend_target_allowed?/3`-legal,
  strictly-adjacent tile only — there is no way to construct an illegal click).
- **7695 Owner reviews a full steward-action log on return** — PASS, live this session.
  Player 12's own `data-test="steward-log"` panel listed 4 entries including the new
  `production_set` and `emergency_defense` actions, both correctly attributed to
  `qa-901-a@broken-oaths.test`.
- **7696 Provable sabotage dings the steward's Honor** — NOT TESTED via UI (unchanged from
  prior sessions — no client-side path can ever construct an illegal defend target, since
  every rendered defend button is server-computed from the unit's own real
  `adjacent_tile_ids`; the sabotage penalty is a defense-in-depth guard against a crafted/
  malicious raw event, not something an honest UI click can trigger). Covered at the
  spex/unit level per `Stewardship.apply_sabotage_penalty/1`'s own tests.

## Evidence

Screenshots at `.code_my_spec/qa/910/screenshots/`:
- `re3_01_vassals_panel_open.png` — Vassals panel showing the new production form
  ("City 1 / Settler ▾ / Steward: Set Production") and the "Under attack! / Warrior
  (50/100) / Defend → Tile N×6" section, all live for offline player 12
- `re3_02_production_set_worker.png` — after submitting the production form
- `re3_04_emergency_defend_applied.png` — after clicking a real Defend button
- `re3_05_no_defend_when_not_attacked.png` — Vassals panel with the unit healed —
  emergency section entirely absent
- `re3_07_owner_steward_log.png` — player 12's own steward log listing all 4 actions

psql verification: `game_production_items` (worker item queued on city 9), `game_units`
(unit 444 tile_id 505→504), `game_steward_logs` (5 total rows across all sessions;
`production_set` and `emergency_defense` rows added this session, both
`steward_player_id=11, owner_player_id=12, sabotage=false`).

## Issues Filed

None — both previously-flagged UI-coverage gaps are closed; no new defects found.
