# Qa Journey Result

## Status

partial

## Journey Results

### new_player_settles

**Result: PASS**

Executed against world 1 ("QA World", corrected from the plan's stale id 6 — see Notes). Registered a fresh email (`qa-journey-newplayer-1784365084@broken-oaths.test`), confirmed via the magic link at `/dev/mailbox`, joined world 1 via `[data-test='join-world-1']`.

Steps and observations:
1. Register → `/dev/mailbox` → magic link → "Confirm and stay logged in" → landed logged in on `/`. Clean, no console errors.
2. `/play` world picker showed "QA World" with a `Join` button (`data-test='join-world-1'`) — confirms the plan's corrected world id.
3. Landed on `/play/1`: cloud-wrapped globe, one clear bubble around spawn, lord + settler visible, gold badge showed 50. Matches exactly.
4. Left-clicked the settler (tile 3423) — unit panel opened: "Settler", HP 50/50, Movement 2/2, Found City button. Matches.
5. Right-clicked an adjacent land tile (3424) — settler moved immediately, tile_id updated in the same round trip (confirmed via psql). Movement appeared full (2/2) in the follow-up screenshot only because this world's `turn_seconds` is 10s and several turns ticked between the move and the screenshot, recharging movement — the spend itself was real and instantaneous.
6. Clicked Found City — succeeded immediately (no spacing-error toast; the new player's spawn point was naturally far from anything). A "Barbarian camps are forming" toast appeared instead (expected first-city-founded flavor text). This is itself a legitimate outcome per the plan ("that toast is itself an expected outcome to note" — in this case the *absence* of a spacing conflict was expected for a brand-new spawn).
7. City appeared on the settler's tile; settler was gone; city panel showed size 1, default name "City 1", food 12/20 +6/turn, full production catalog (Settler disabled with "Needs a second citizen to spare", Worker 60, Warrior 40), Worked Tiles list with center marked Free.
8. Queued a Warrior via the catalog — current-production row showed "Warrior 0/40" with a progress bar. Exact match.

No console errors, no refreshes, no workarounds. Crosses stories 873/875/876/877/878/879 cleanly.

### returning_lord_manages_city

**Result: FAIL**

Logged in as `qa@broken-oaths.test` (password form), entered world 1 via Enter (`data-test='join-world-1'`, label reads "Enter" for a joined world — same underlying button/event as "Join").

**Blocking bug found at step 3** ("left-click own city"): the QA account's capital (city id 1, tile 14725) has a `bronze_spearman` unit garrisoned on the same tile. The board hook's `click()` hit-test prioritizes units over cities on the same tile (by design). Left-clicking tile 14725 therefore selects the bronze_spearman — which crashes the entire `GameLive.Play` LiveView process (`FunctionClauseError` in `UnitPanel.unit_type_label/1`, no clause for `:bronze_spearman`; confirmed via dev server log, occurred 9 times total across the session as I re-triggered it). The client silently reconnects (LiveView auto-remount) with no visible error toast, and the click has no effect — the city panel never opens. **A real player in this exact situation (any established, defended city in Bronze Age) cannot open their own city panel via the board at all.** Filed as issue `b8f4ce10` (critical).

I relocated the blocking unit off the city tile via the dev-only QA control surface (`PATCH /dev/qa/worlds/1/units/379`) — not something a real player can do — to verify the remaining steps still work correctly once the city panel is reachable:

4. City panel opened: name "City 1", size 6, food/production stats, Worked Tiles list (center Free), Build catalog. Renamed to "Oakhaven" via the name form — header updated immediately and the name persisted across a full page reload (reselecting the city afterward showed "Oakhaven"). Matches.
5. Queued Warrior then Worker — current showed "Warrior 0/40". Clicked the Worker's move-up arrow (`data-test='queue-move-up-<id>'`) — order swapped correctly (confirmed via psql: position 1/2 flipped from warrior/worker to worker/warrior), current production became "Worker 0/60". Matches.
6. Clicked Abandon on the current item (Worker) — it disappeared; Warrior became current at its own banked value (0), confirmed via psql and screenshot. Matches.
7. Advanced one turn boundary deterministically via `/dev/qa/worlds/1/step` (rather than idling the real 10s clock) — food rose (100468→100482, +14) and the current build's banked value rose (0→11, matching the displayed "+11/turn" hammer rate) in the same step; turn counter in the top bar ticked 9918→9919. Matches.

Restored the blocking unit's position and resumed the world afterward.

**Verdict rationale:** step 3 as written in the plan cannot be completed by a real user through the UI in the current app state — it requires a critical, reproducible crash bug to not exist. Steps 4-7 all work correctly once that blocker is bypassed, but the journey as a whole fails because its very first city-management action is unreachable for a normal player.

### worker_improves_the_land

**Result: PASS**

Continued in the same session as the QA account, world 1.

1. Selected the QA account's idle worker (unit 378, type `worker` — this type has a `unit_type_label/1` clause, so selection works fine, unlike the bronze_spearman crash above).
2. Unit panel showed Build actions gated by terrain: on a `Plains · Rainforest` tile only "Build Road" appeared (no Farm/Mine — most of this city's territory is rainforest-covered); on a clean flat `Plains` tile (14739), "Build Farm" and "Build Road" appeared (no Mine, no Pasture — correctly gated). Confirmed by scanning ~30 territory tiles' terrain via the tile-info panel (`data-test="tile-terrain"`) before choosing a target.
3. Moved the worker (right-click) to a flat, unimproved Plains tile (14723, confirmed clean via terrain scan) and clicked Build Farm — "Digging Farm — 0/3 turns" badge appeared immediately.
4. Advanced exactly 3 turn boundaries via `/dev/qa/worlds/1/step` — psql confirmed the improvement's `progress` reached 3/3 and `status` flipped to `complete`. Reselected the worker in the UI: no more digging badge, movement recharged to 2/2.
5. Clicked Build Farm again on the same (now-complete) tile — got the exact expected error: "This tile already has a completed improvement." Matches.
6. In the city panel, clicked "Work" on the newly-farmed tile 14723 — it moved from the Work list to the Unwork (worked) list, and food/turn rose from +11/turn to +12/turn immediately in the display. A subsequent stepped turn boundary confirmed the extra food accrued (banked production also rose, consistent with the new yield).

All plan steps produced the exact expected outcome with no workarounds needed for the tested actions themselves.

**Side finding (does not affect this journey's PASS, but is a real bug):** assigning the "Work" tile in step 6 grew the city's `worked_tiles` from 6 entries to 7 while `size` stayed at 6 — `assign_worked_tile`'s server-side validation never checks the population cap (`length(worked_tiles) < size`) before adding a tile with no paired unassignment, even though a changeset-level `validate_worked_tiles_within_size/1` rule exists specifically to prevent this and is simply never invoked on this write path (`persist_worked_tiles!/2` uses a raw `Repo.update_all`). Filed as issue `7509c453` (high). I unassigned the extra tile afterward to restore the city to its correct 6/6 worked-tile state.

### empire_expands

**Result: PARTIAL**

Continued in the same session, world 1, city "Oakhaven" (size 6, qualifies as size-2+).

1. Selected Oakhaven (size 6) — Settler option enabled in the Build catalog (unlike the size-1 "City 1" from `new_player_settles`, which showed it disabled with "Needs a second citizen to spare" — that sub-check was already verified in journey 1's evidence).
2. Queued Settler (100 cost) — current production showed "Settler 0/100".
3. Stepped turns deterministically (`/dev/qa/worlds/1/step`, +11 production/turn) until banked reached 100. The settler unit spawned correctly (new `game_units` row, type `settler`, at the city's tile — confirmed via psql).
   - **Deviation found:** the plan expects "city size drops by one at that boundary." It did not. Checked `game_cities.size` via psql immediately after the spawning step: still 6, never observed at 5. Traced the cause: `Turn.tick/1`'s phase order runs settler pop-cost (phase 3, `Production.complete/3`) and growth (phase 5, `Yields.grow/3`) in the *same* tick. This world's city has an enormous banked food surplus (~100,000+, accumulated over many QA sessions) — vastly past the 60-food threshold needed to grow 5→6 in the Bronze Age — so growth silently re-fills the population loss in the identical tick, making the pop cost externally unobservable. Filed as issue `63300098` (medium).
4. Selected the spawned settler, clicked Found City right at the capital's own tile — got the exact expected toast: "Too close to an existing city." The settler survived (confirmed still present, HP 50/50, selectable) with no orders consumed. Matches.
5. Right-clicked a tile 4+ hexes out (tile 21103, reached via an 18-tile pathed order into partially-fogged territory) — order queued (`kind: move`, 18-tile path, confirmed via psql). Stepped turns; the settler visibly marched down the path across multiple boundaries (confirmed intermediate tile_ids advancing: 20735 → 20832 → 20925 → 21016 → 21103) exactly as expected — "orders into fog are legal" confirmed.
6. Found City at the destination (21103): new city "City 2" appeared, size 1, exactly 7 territory tiles (`{21060,21061,21103,21104,21145,28300,28341}` — the founding ring). Progress panel showed "Cities founded: 2". Oakhaven's own stats (size 6, territory count, food) were unaffected by the act of founding the second city. Matches.

**Verdict rationale:** 3 of the 4 checkable behaviors in this journey (spacing enforcement with the correct human-readable toast + settler survival, marching across boundaries including into fog, and a correctly-bootstrapped second city with an untouched capital) worked exactly as the plan describes, with no workarounds needed. The remaining behavior — "settler production pays its population cost" — is explicitly named in the journey's own expected-outcome summary and did not hold under test; this is a real, reproducible bug (not a plan error), so the journey is graded partial rather than a clean pass.

## Issues

### b8f4ce10 — Selecting a bronze_spearman unit crashes GameLive.Play (critical)

Left-clicking (or otherwise selecting) any `:bronze_spearman` unit crashes the `GameLive.Play` LiveView process (`FunctionClauseError` in `UnitPanel.unit_type_label/1` — no clause for `:bronze_spearman`). Blocks selecting/managing Bronze Age warriors entirely, and blocks selecting a player's own city via left-click whenever a bronze_spearman is garrisoned on the city's tile (units win the click hit-test over cities on the same tile). Directly caused `returning_lord_manages_city` to fail its very first city-management step. See `lib/broken_oaths_web/live/game_live/unit_panel.ex:149-155`.

### 7509c453 — assign_worked_tile has no population-cap check (high)

`WorldServer.validate_assign/3` never checks `length(city.worked_tiles) < city.size` before adding a worked tile with no paired unassignment. A city can be assigned more worked tiles than its size supports, permanently over-harvesting yield — reproduces on the very first ordinary "assign a farmed tile" action (`worker_improves_the_land`'s own last step). The changeset's own `validate_worked_tiles_within_size/1` rule exists to prevent exactly this but is never invoked, since the write path uses a raw `Repo.update_all`. See `lib/broken_oaths/game/world_server.ex:1778-1814`.

### 63300098 — Settler's population cost is masked by same-tick growth (medium)

`Turn.tick/1` resolves a completed settler's population cost (phase 3) and city growth (phase 5) in the same turn boundary. A city with food banked past its next growth threshold (trivially true for any long-lived, well-fed city) has the settler's pop cost silently refunded by growth in the identical tick, so city size never externally drops — defeating the intended settler/population tradeoff. Reproduces `empire_expands`'s own step-3 expectation failing to hold. See `lib/broken_oaths/game/turn.ex` (city-loop phase ordering) and `lib/broken_oaths/game/yields.ex:304-318`.

## Evidence

- `.code_my_spec/qa/journey_plan.md` — corrected in-flight: world ids 6→1 (QA World) and 10→2 (QA World Fill Test), plus all `/play/6` and "world 6" references, per the verified psql world table.

### new_player_settles
- `.code_my_spec/qa/journeys/screenshots/j1_00_register_page.png`
- `.code_my_spec/qa/journeys/screenshots/j1_01_registered.png`
- `.code_my_spec/qa/journeys/screenshots/j1_02_mailbox.png`
- `.code_my_spec/qa/journeys/screenshots/j1_03_confirmed_logged_in.png`
- `.code_my_spec/qa/journeys/screenshots/j1_04_logged_in_home.png`
- `.code_my_spec/qa/journeys/screenshots/j1_05_world_picker.png`
- `.code_my_spec/qa/journeys/screenshots/j1_06_spawned_globe.png`
- `.code_my_spec/qa/journeys/screenshots/j1_07_settler_selected.png`
- `.code_my_spec/qa/journeys/screenshots/j1_08_settler_moved.png`
- `.code_my_spec/qa/journeys/screenshots/j1_09_found_city.png`
- `.code_my_spec/qa/journeys/screenshots/j1_10_city_panel.png`
- `.code_my_spec/qa/journeys/screenshots/j1_11_warrior_queued.png`

### returning_lord_manages_city
- `.code_my_spec/qa/journeys/screenshots/j2_00_login_page.png`
- `.code_my_spec/qa/journeys/screenshots/j2_01_logged_in.png`
- `.code_my_spec/qa/journeys/screenshots/j2_02_world_picker.png`
- `.code_my_spec/qa/journeys/screenshots/j2_03_entered_world.png`
- `.code_my_spec/qa/journeys/screenshots/j2_04_city_panel_open.png`
- `.code_my_spec/qa/journeys/screenshots/j2_05_BUG_city_unreachable.png` — evidence of the crash/reconnect after clicking the garrisoned tile
- `.code_my_spec/qa/journeys/screenshots/j2_06_city_panel_after_workaround.png`
- `.code_my_spec/qa/journeys/screenshots/j2_07_renamed.png`
- `.code_my_spec/qa/journeys/screenshots/j2_08_renamed_survives_reload.png`
- `.code_my_spec/qa/journeys/screenshots/j2_09_queue_two_items.png`
- `.code_my_spec/qa/journeys/screenshots/j2_10_queue_reordered.png`
- `.code_my_spec/qa/journeys/screenshots/j2_11_abandoned_current.png`
- `.code_my_spec/qa/journeys/screenshots/j2_12_turn_boundary_advanced.png`

### worker_improves_the_land
- `.code_my_spec/qa/journeys/screenshots/j3_00_worker_selected.png`
- `.code_my_spec/qa/journeys/screenshots/j3_01_worker_at_14742.png`
- `.code_my_spec/qa/journeys/screenshots/j3_02_worker_moved_14743.png`
- `.code_my_spec/qa/journeys/screenshots/j3_03_worker_at_14739_plains.png`
- `.code_my_spec/qa/journeys/screenshots/j3_04_build_farm_started.png`
- `.code_my_spec/qa/journeys/screenshots/j3_05_farm_complete.png`
- `.code_my_spec/qa/journeys/screenshots/j3_06_duplicate_build_error.png`
- `.code_my_spec/qa/journeys/screenshots/j3_07_city_panel_before_work.png`
- `.code_my_spec/qa/journeys/screenshots/j3_08_tile_assigned.png`
- `.code_my_spec/qa/journeys/screenshots/j3_09_BUG_over_cap_worked_tiles.png` — evidence of the worked-tiles-exceed-size bug

### empire_expands
- `.code_my_spec/qa/journeys/screenshots/j4_00_city_selected.png`
- `.code_my_spec/qa/journeys/screenshots/j4_01_settler_queued.png`
- `.code_my_spec/qa/journeys/screenshots/j4_02_settler_selected.png`
- `.code_my_spec/qa/journeys/screenshots/j4_03_too_close_toast.png`
- `.code_my_spec/qa/journeys/screenshots/j4_04_settler_arrived_far.png`
- `.code_my_spec/qa/journeys/screenshots/j4_05_second_city_founded.png`
