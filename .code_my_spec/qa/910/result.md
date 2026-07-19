# Qa Result — 910 Feudal Stewardship

## Status: partial

## Summary

The one click-through affordance this story ships — "Steward: Collect Bank" — is real, correct,
and verified BIDIRECTIONALLY through genuine clicks: a lord sweeping an offline vassal's bank,
and (separately) each of two allied peers sweeping the other's bank while offline, proving true
symmetry rather than a one-way test. Every sweep correctly moved 100% of the swept gold to the
OWNER (never the steward), left the steward's own treasury untouched, and wrote a
`game_steward_logs` row the owner can review. "Vassal cannot steward own lord" is confirmed by
UI-absence + code structure (no click exists to fail — the affordance simply never renders in
that direction), not a live negative click. Production stewardship and emergency defense have NO
click-through UI at all in the shipped client — only bare `handle_event` clauses reachable via
`attempt_event`/spex, confirmed by reading `play.ex`'s full render tree. This keeps the story at
`partial`: the shipped mechanic (bank stewardship) is solid, but roughly half the story's
acceptance criteria (production stewardship, emergency defense, fellow-vassal-specific coverage)
have no real-UI surface to drive at all.

## Scenarios

- **7686 Lord and fellow vassal can steward an offline household member** — PASS (lord half only).
  Real `steward-collect-bank` click via the Vassals panel: player 12's offline bank (66, later
  100) swept entirely to player 12's own gold; a `game_steward_logs` row recorded
  `steward_player_id=11, owner_player_id=12, action=bank_collect`. "Fellow vassal" half not
  testable — World 3 has only one vassal per lord, no 3rd sibling vassal to test peer-stewarding.
- **7687 A vassal cannot steward their own lord** — PASS by structural/UI-absence verification.
  `vassals_panel` is rendered from `Game.vassals(world, user)` — the CURRENT user's own vassals
  only — so relationship id=2 (lord=11, vassal=12) never surfaces ANY steward affordance on
  player 12's own UI targeting player 11 via the lord channel; confirmed by reviewing every
  screenshot of player 12's Vassals panel across the session (it only ever lists player 12's OWN
  vassal, player 11, via the separate, legitimate relationship id=3).
- **7688 Allied peers can steward each other symmetrically** — PASS, fully live, BOTH directions.
  Player 11 (online) swept player 12 (offline)'s bank via the Alliance panel (+100 to player 12,
  steward log entry). Then roles reversed: player 12 (online) swept player 11 (offline)'s bank via
  the SAME alliance-panel button (+21 to player 11, steward log entry, player 12's own gold
  unaffected) — genuine bidirectional proof of symmetry, not just code review.
- **7689 Steward sweeps the offline bank entirely to the owner** — PASS. Every sweep this session
  (3 total, both directions) moved the FULL `banked_gold` amount to the owner's `gold`, reset
  `banked_gold` to 0, and left the steward's own `gold` byte-for-byte unchanged.
- **7690 Steward queues a whitelisted constructive build** — NOT TESTED. No click-through UI
  exists (`steward_queue_production` is a bare `handle_event` clause with no button/form anywhere
  in `play.ex`'s render tree).
- **7691 Steward cannot disband a unit or cancel an in-progress build** — NOT TESTED (same reason
  as 7690 — enforced structurally by the ABSENCE of a `steward_disband_unit`/
  `steward_cancel_production_item` UI path, per the module's own moduledoc, but not click-verified).
- **7692 Steward cannot move units when the owner is not under attack** — NOT TESTED, no UI.
- **7693 Ally issues a defensive order while the offline owner is under attack** — NOT TESTED, no UI.
- **7694 Steward cannot use the emergency window to march the army off or attack** — NOT TESTED, no UI.
- **7695 Owner reviews a full steward-action log on return** — PASS. Player 12's own
  `data-test="steward-log"` panel correctly listed both bank-collect actions taken on their behalf
  by player 11 ("qa-901-a@broken-oaths.test — bank_collect" ×2), scoped correctly to THEIR OWN
  log (player 11's own steward-log correctly showed "No steward actions taken on your behalf yet"
  at the same point, since player 11 was the actor, not the target, in those two actions).
- **7696 Provable sabotage dings the steward's Honor** — NOT TESTED. No emergency-defense UI to
  trigger a sabotage attempt through; `sabotage: false` on every real steward log row produced
  this session (all legitimate bank collects).

## Evidence

Screenshots at `.code_my_spec/qa/910/screenshots/`:
- `re2_01_steward_log_lord_vassal.png` — player 11's own (empty) steward log, confirming correct
  per-owner scoping
- `re2_02_steward_log_symmetric_ally.png` — player 12's steward log showing both bank_collect
  entries from player 11

psql verification: `game_steward_logs` (3 rows across the session — 2 lord-path + ally-path
sweeps of player 12's bank by player 11, 1 ally-path sweep of player 11's bank by player 12, all
`sabotage=false`), `game_players.gold`/`banked_gold` deltas matching exactly on every sweep.

## Issues Filed

- (see below) Filed one issue noting the missing click-through UI for production stewardship and
  emergency defense as a coverage gap, not a functional bug (the underlying mechanics are
  unit/spex-tested).
