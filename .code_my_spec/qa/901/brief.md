# Qa Story Brief — 901 Cooperative Barbarian Fighting

## Tool

web (vibium CLI via Bash, sandbox disabled) plus `psql broken_oaths_dev` for ground truth. No
`mix`/`iex`/`mix run` at any point — read all state via psql per `plan.md`'s System Issues
section (a "safe" mix read killed the shared dev server in a prior session).

## Auth

Purpose-built World 3 ("QA World (Multiplayer)", id 3, turn_seconds=5) with two pre-staged,
pre-confirmed accounts — password login, no magic-link needed:

- Player A: `qa-901-a@broken-oaths.test` / `qa-password-123!` — `game_players.id`=11,
  `users.id`=11, warrior unit **#312 @ tile 347**, lord unit #212 @ tile 506.
- Player B: `qa-901-b@broken-oaths.test` / `qa-password-123!` — `game_players.id`=12,
  `users.id`=12, warrior unit **#313 @ tile 348**, lord unit #214 @ tile 266.

Login flow (per `plan.md`):

1. `vibium go "http://localhost:4050/users/log-in"`
2. Fill `#login_form_password input[name="user[email]"]` and
   `input[name="user[password]"]`, submit.
3. `vibium go "http://localhost:4050/play/3"`.

To switch identities in the same tab (session cookie shared): visit `/`, click
`a[href='/users/log-out']`, then repeat the login flow for the other user. Prefer sequential
single-tab identity switching — a second tab's LiveView socket unreliably reconnects after
logout+relogin (per plan.md and prior 899/900 sessions). This story only needs **one** identity
switch (A does its work, then switch once to B) — sequence the plan to minimize switches.

## Seeds

Already seeded — no new seed script needed. Ground truth confirmed via psql before writing this
brief:

- `game_units`: unit 312 (player 11, warrior, tile 347, hp 100, movement 1), unit 313 (player 12,
  warrior, tile 348, hp 100, movement 1). No barbarian/camp-spawned units on the map yet.
- `game_camps`: id 47, world_id 3, tile_id 352, hp 100, spawn_counter 0, destroyed_at null — the
  shared target. 14 other camps exist in world 3 (ids 48-61, various tiles) for a possible
  sole-attacker side-test.
- `game_players`: player 11 gold 50, player 12 gold 50.
- `game_known_players`: both directions already present (world_id=3, viewer 11→discovered 12 and
  viewer 12→discovered 11) — mutual discovery is pre-staged, alliance panel candidates should
  show immediately.
- Per-hit camp damage is flat (no roll): a full-HP warrior deals exactly **10** per swing (see
  `Game.Combat.camp_damage/2`, confirmed in story 894 QA). Camp destroy reward is a flat
  **30 gold** (`Camps.destroy_reward/0`), split via `Cooperation.split_bounty/3`
  (largest-remainder proportional split — a 70/30 damage split pays exactly 21/9 gold, no
  rounding loss).

Re-confirm state immediately before testing:

    psql broken_oaths_dev -c "select id, player_id, tile_id, hp, movement from game_units where id in (312,313);"
    psql broken_oaths_dev -c "select id, tile_id, hp, destroyed_at from game_camps where id=47;"
    psql broken_oaths_dev -c "select id, gold from game_players where id in (11,12);"

If any of this has drifted (e.g. a unit is dead or the camp already damaged by something else),
STOP and report — do not attempt to re-seed.

## What To Test

### 1. Alliance propose/accept (criteria 7623, and the coordination precondition for the rest)

- As Player A on `/play/3`: click `[data-test='alliance-button']` to open
  `[data-test='alliance-panel']`. Confirm `[data-test='ally-candidate-12']` (Player B's
  `users.id`) is listed under "Propose". Click its `[data-test='propose-alliance']` button.
- Confirm via psql: `select * from game_alliances where world_id=3;` shows one row,
  `proposer_player_id=11`, `status='proposed'`.
- Switch identity to Player B: open the alliance panel, confirm the pending row
  `[data-test='alliance-<id>']` shows `[data-test='alliance-status-pending']` is NOT shown to B
  (B is the acceptor) and `[data-test='accept-alliance']` IS present. Click it.
- Confirm via psql: the same `game_alliances` row now has `status='accepted'`.
- Screenshot both the propose and accept states.

### 2. Shared-target cumulative damage (criteria 7611, 7612)

Both warriors are already adjacent to camp 47 (tile 352) — confirmed via seed ground truth, no
marching needed. Attack is a right-click on the camp's own tile; the client hook infers
`target_camp_id` automatically (per `board_click.sh`'s doc comment and story 894 QA precedent):

    ./board_click.sh 352 right

- While still logged in as A (after the alliance propose step): attack camp 47 **7 times**,
  waiting for a turn boundary between each swing (turn_seconds=5 — poll
  `select movement from game_units where id=312;` until it's back to 1 before re-attacking, or
  just sleep ~6s between swings to be safe). After each swing, confirm via psql that
  `game_camps.hp` for id 47 dropped by exactly 10 and that unit 312's `hp` is unchanged (camps
  never counter). Expect camp hp: 100 → 90 → 80 → 70 → 60 → 50 → 40 → 30 after A's 7th swing.
- Record player 11's gold after these 7 swings — should still be 50 (camp not destroyed yet, no
  bounty paid mid-siege).
- This proves cumulative shared-target damage accrual (7611) and sets up "felled over multiple
  turns" (7612) to be demonstrated jointly with B's hits below.

### 3. Proportional bounty split — THE CRUX (criterion 7614)

- Switch identity to Player B. Record `game_players.gold` for BOTH 11 and 12 via psql
  immediately before B's first swing (expect 11=50, 12=50 — confirms A's swings alone didn't pay
  out yet, since the camp is still alive).
- Attack camp 47 **3 times** as B (same `./board_click.sh 352 right`, same ~6s wait between
  swings for movement/turn recharge). Poll `game_camps.hp` after each: 30 → 20 → 10 → **0** on
  the 3rd swing.
- On the swing that brings hp to 0, confirm via psql in the SAME query round-trip window:
  - `game_camps`: `hp=0`, `destroyed_at` is now set (not null).
  - `game_players`: player 11's gold rose from 50 to **71** (+21), player 12's gold rose from 50
    to **59** (+9). Total damage was A=70 (7×10), B=30 (3×10) → 70:30 ratio → 30-gold bounty
    splits 21:9 exactly (largest-remainder method, no rounding loss — verify
    `21 + 9 == 30`).
- This is the crux assertion — capture the exact psql before/after gold rows as evidence
  (`.code_my_spec/qa/901/responses/`).

### 4. Sole-attacker full bounty (criterion 7615) — attempt if stageable

- Before starting the cooperative kill above (or after, time permitting), check whether any of
  the other 14 camps in world 3 (`game_camps` ids 48-61) is already visible/adjacent to either
  player's lord (unit 212 @ tile 506, unit 214 @ tile 266) via `./board_state.sh` (its `camps`
  array only lists camps in the querying player's fog window). If one is reachable in 1-2 hops
  without excessive marching risk, have ONE player solo-damage and destroy it, confirm via psql
  that ONLY that player's gold rose by the full 30 (the other player's gold is untouched by this
  particular camp's destruction).
- If no camp is reachable within a reasonable turn budget, do NOT spend excessive session time
  marching into unknown, possibly-lethal territory — note this as not independently re-staged
  live this session and back it with the passing spex
  (`test/spex/901_cooperative_barbarian_fighting/criterion_7615_sole_attacker_keeps_the_whole_bounty_spex.exs`).
  Cross-reference: `Cooperation.split_bounty/3`'s moduledoc explicitly documents "a SOLE
  contributor's 100% share is still the WHOLE reward, never a smaller default cut" — and the
  proportional-split math already proven live in step 3 (a 70:30 *contributor* ratio paying
  21:9) is the same code path a 100:0 ratio would hit (100% share -> the full 30, 0% share -> 0).

### 5. Cleared border opens land (criterion 7616)

- Immediately after camp 47 is destroyed (step 3): confirm via `./board_state.sh` (as either
  player) that camp id 47 no longer appears in the `camps` array (or appears with
  `destroyed_at` set, matching psql).
- Right-click tile 352 again with a warrior now adjacent to it
  (`./board_click.sh 352 right`) — since there's no longer a camp there, the client hook should
  issue a MOVE order instead of an attack. Confirm via psql that the attacking unit's `tile_id`
  updates toward/onto 352 (or its `queued` movement path targets it) rather than another
  `game:combat` push firing. This proves the tile is normal, walkable terrain again — the
  cooperative kill opened the border.
- Screenshot the board state showing the camp gone / the tile now occupied or move-ordered.

## Result Path

No `result.md` file — findings are filed via `create_issue` as discovered; the session concludes
with one `submit_qa_result` call. Screenshots saved to `.code_my_spec/qa/901/screenshots/`; psql
before/after evidence (especially the gold-split proof from step 3) saved as text captures under
`.code_my_spec/qa/901/responses/`.

## Setup Notes

- turn_seconds=5 is fast — do not leave the browser idle for long stretches between commands;
  the world keeps ticking (barbarians may spawn from camp 47 every 3 turns and roam — expected,
  not a bug; stay focused on the camp assault + gold math and don't get drawn into unplanned
  barbarian-warrior skirmishes unless one conveniently demonstrates criterion 7613's "counters
  only its attacker" for free).
- Single shared vibium browser — exclusive to this session. Sequential single-tab identity
  switching only (per plan.md and prior 899/900 session notes about socket reconnect
  reliability).
- `./board_click.sh` / `./board_state.sh` (paths under
  `.code_my_spec/qa/scripts/`) require the vibium daemon already navigated to `/play/3` and
  logged in, sandbox disabled. `psql broken_oaths_dev` also needs the sandbox disabled (Unix
  socket outside the default allowlist).
- If the seeded state has drifted badly before you even start (e.g. a warrior already dead, camp
  47 already damaged/destroyed by something else) — STOP and report; do not attempt to reseed
  (that requires `mix run`, which is banned this session).
- Criterion 7624 ("even undiscovered attackers share the bounty") is NOT in this session's
  required scope per the launching agent's instructions (both players are already mutually
  discovered in this seed, so it can't be demonstrated live here anyway without an undiscovered
  third party) — rests on the passing spex
  (`criterion_7624_even_undiscovered_attackers_share_the_bounty_spex.exs`) and on
  `Cooperation.record_damage/4`'s moduledoc, which documents that nothing in the damage-ledger or
  split path ever checks `Alliance`/discovery status.
