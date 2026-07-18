# Qa Journey Result

## Status

pass

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

**Result: PASS** (re-verified — was FAIL on issue `b8f4ce10`, now fixed)

Re-run against world 1 to verify the `b8f4ce10` fix (`UnitPanel.unit_type_label/1` now has a `:bronze_spearman` clause plus a catch-all fallback — see `lib/broken_oaths_web/live/game_live/unit_panel.ex:150-163`). Logged in as `qa@broken-oaths.test` (password form), entered world 1.

1. **Crash check (the crux):** left-clicked tile 14725 (the QA account's capital, Oakhaven — still garrisoned by `bronze_spearman` unit 379, same setup as the original failing run). The unit panel opened cleanly showing **"Bronze Spearman"**, HP 120/120, Movement 1/1, no orders queued. No crash, no silent reconnect: `window.location.href` stayed on `/play/1` throughout, `window.liveSocket.isConnected()` remained `true`, and the dev server log showed the `select_unit` event handled and replied normally with zero exception traces (previously this reproduced a `FunctionClauseError` 9 times in the original session). Screenshot: `j2_rerun_01_bronze_spearman_selected_no_crash.png`.
2. **Reaching the city panel:** as anticipated in the prompt, the unit still wins the click hit-test over the city on the same tile (by design, unrelated to the fix), so relocated unit 379 off tile 14725 to the empty adjacent tile 14724 via `PATCH /dev/qa/worlds/1/units/379` — legitimate QA-surface use, not something a real player can do, but the crash itself (the actual regression under test) is independently confirmed gone in step 1 above. With the tile clear, left-clicking 14725 opened the city panel: name "Oakhaven" (from a prior session's rename), size 6. Screenshot: `j2_rerun_02_city_panel_open.png`.
3. **Rename:** submitted the name form with "Oakhaven II" — header updated immediately (`data-test='city-name'`). Reloaded `/play/1` fully, reselected the city (tile 14725) — name still read "Oakhaven II", confirming the rename persisted across a full page reload. Screenshot: `j2_rerun_03_renamed_survives_reload.png`.
4. **Queue two items + reorder:** clicked `production-option-warrior` then `production-option-worker`. Confirmed via psql: `game_production_items` held `warrior` (position 1, current) and `worker` (position 2, queued). Clicked the worker's `data-test='queue-move-up-48'` arrow — psql confirmed the swap (worker → position 1, warrior → position 2, each item's banked production carried with it unchanged). UI's current-production line updated to "Worker 11/60" in the same round trip. Screenshot: `j2_rerun_04_queue_two_items.png`, `j2_rerun_05_queue_reordered.png`.
5. **Abandon current:** clicked `data-test='cancel-current-production'` (the actual button label/selector is "Abandon" — matches the plan's step). The worker item disappeared; warrior became current at its own already-banked value (33/40, not reset to 0), confirmed via psql and the UI's current-production line ("Warrior 33/40"). Screenshot: `j2_rerun_06_abandoned_current.png`.
6. **Turn boundary:** the original warrior item actually completed production before this step could be staged deterministically (its 33/40 banked value cleared the 40 cost within a couple of live 10s ticks), so a **new** Warrior was queued (0/40) to get a clean boundary to test. Paused the world (`POST /dev/qa/worlds/1/pause`), captured baseline (food 103154, banked 0), stepped exactly one turn (`POST .../step`, turn 10114→10115). psql confirmed food rose 103154→103168 (+14) and banked production rose 0→11 in the same boundary; the UI's current-production line and top-bar turn counter matched exactly ("Warrior 11/40", "10115"). Screenshot: `j2_rerun_07_turn_boundary_advanced.png`.

**Cleanup:** the warrior queued in step 4/completed mid-session spawned a real unit (id 424) on tile 14725 while unit 379 was parked aside — to restore 379 to its original tile 14725 without deleting a legitimately-produced unit, paused the world, moved unit 424 one tile over to the empty 14708 (a normal QA-surface relocation, not a deletion), moved 379 back onto 14725, then resumed the world (confirmed `paused: false` via `GET /dev/qa/worlds/1`).

**Verdict rationale:** every plan step now works exactly as written, with the single crash-avoidance workaround the prompt itself anticipated (relocating the garrisoned unit to reach the city panel — a limitation of click hit-testing "by design," not the bug under test). The bug under test — selecting/being blocked by a `bronze_spearman` — is confirmed fixed: it no longer crashes the LiveView under any circumstance exercised in this session.

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

**Result: PASS** (re-verified — was PARTIAL on issue `63300098`, now fixed)

Re-run against world 1 to verify the `63300098` fix: `Turn.tick/1` now tracks which city ids paid a settler's population cost each tick and `Yields.grow/4`'s caller (`grow_cities/2`) skips growth for those cities on that same tick only (`lib/broken_oaths/game/turn.ex` phase-order doc + `grow_cities/2`). Used City 2 (id 12, size 6, tile 21103 — an empty tile with no garrisoned unit, avoiding the need to relocate the bronze_spearman again) as the size-2+ producing city; Oakhaven (id 1) is also size 6 and would have worked equally well.

1. Selected City 2 (size 6) — Settler option enabled (`data-disabled="false"`, cost 100). Queued it — current production showed "Settler 0/100". Screenshot: `j4_rerun_00_settler_queued.png`.
2. **The crux — pop-cost observability:** paused the world, then stepped turns one at a time (12 steps, +9 production/turn), checking `game_cities.size` and the production queue via psql after **every single step** (not just at the end). Size held at 6 for steps 1-11 (queue climbing 9/100 → 99/100). At **step 12**, the queue emptied (settler completed) and in that exact same step **`game_cities.size` dropped from 6 to 5** — confirmed via psql immediately, before any further step could run. The settler unit (id 426) was confirmed spawned on the city's tile in the same read. The UI's `city-size` badge independently read "5" at this point too. Screenshot: `j4_rerun_01_size_dropped_to_5.png`. **This is the exact behavior that failed before the fix** (previously size never left 6 because growth silently re-filled it in the same tick).
3. Stepped one additional turn as a mechanism check: size regrew 5→6 in the very next tick, exactly as the fix's own code comments describe ("growth ... never for a city that already paid a settler's population cost in phase 3 THIS SAME tick" — the skip is scoped to a single tick, not permanent; this city's ~2300+ banked food is vastly past the 60-food threshold for 5→6, so growth resumes normally the very next boundary). This confirms the fix makes the −1 observable at the completion boundary without changing the eventual growth trajectory — matching the intended, narrowly-scoped fix.
4. Selected the settler, clicked Found City on the parent city's own tile — got the exact expected toast: "Too close to an existing city." (confirmed via `data-test='city-error'` text, captured immediately after the click). The settler survived (confirmed via psql: same id, tile, HP 50/50) with no orders consumed. Screenshot: `j4_rerun_02_too_close_toast.png`.
   - Note: right after the *first* found-city attempt near the capital, an ad-hoc client-side check (`document.body.textContent.includes('reconnect')`) suggested a possible disconnect. Investigated and confirmed this was a **false positive** in my own throwaway check, not a real disconnect or app bug: the matched text is Phoenix LiveView's always-present (CSS-hidden) reconnect-banner markup — `getComputedStyle(el).display` was `block` but `el.offsetParent` was `null` (not actually visible), `window.liveSocket.isConnected()` returned `true` throughout, and the dev server log showed `found_city` handled and replied in 521µs with zero exception traces. No app or QA-tooling issue filed for this — it was purely an artifact of my own imprecise `textContent` substring check, not of `board_click.sh`/`board_state.sh` (which worked correctly throughout).
5. Right-clicked a tile confirmed 4 hexes out via a graph-BFS adjacency check from the city's tile (tile 20927; verified path: 21103→21018(2 hexes, moved immediately)→20973→20927(2 more hexes queued), total 4). Stepped turns; the settler visibly advanced and arrived at 20927 with orders consumed and movement recharged to 2/2, confirmed both via psql and the client's own unit list. Screenshot: `j4_rerun_03_settler_arrived_far.png`.
6. Found City at the destination (20927): new city "City 3" appeared, size 1, exactly 7 territory tiles (`{20880,20881,20926,20927,20928,20972,20973}` — the founding ring). City 2's own stats (size 6, territory count 13, tile_id unchanged) were confirmed unaffected by the act of founding. Screenshot: `j4_rerun_04_second_city_founded.png`.

**Verdict rationale:** the one behavior that failed before — "settler production pays its population cost" being externally observable — now holds exactly as the plan describes, confirmed via a step-by-step psql trace that caught the single-tick window where size sits at 5 before growth (correctly) refills it on a later boundary. All other behaviors (spacing toast + settler survival, marching including a partial-fog path, correctly-bootstrapped second city with an untouched parent) continued to work exactly as in the original partial run. No workarounds were needed for any tested behavior itself (only the same pre-existing "select a unit rather than the city under it" quirk noted in `returning_lord_manages_city`, which was sidestepped here by choosing an unoccupied city tile rather than worked around).

**Cleanup:** world resumed (`paused: false` confirmed via `GET /dev/qa/worlds/1`); no relocated units needed restoring for this journey (City 2's tile was never occupied by a unit).

## Issues

### b8f4ce10 — Selecting a bronze_spearman unit crashes GameLive.Play (critical) — FIXED, verified 2026-07-18

Left-clicking (or otherwise selecting) any `:bronze_spearman` unit crashes the `GameLive.Play` LiveView process (`FunctionClauseError` in `UnitPanel.unit_type_label/1` — no clause for `:bronze_spearman`). Blocks selecting/managing Bronze Age warriors entirely, and blocks selecting a player's own city via left-click whenever a bronze_spearman is garrisoned on the city's tile (units win the click hit-test over cities on the same tile). Directly caused `returning_lord_manages_city` to fail its very first city-management step. See `lib/broken_oaths_web/live/game_live/unit_panel.ex:149-155`.

**Fix verified in the `returning_lord_manages_city` re-run:** `unit_type_label/1` now has an explicit `:bronze_spearman` clause (renders "Bronze Spearman") plus a catch-all fallback for any future unit type. Selecting the bronze_spearman garrisoned on the QA account's capital no longer crashes the LiveView — confirmed via a clean unit panel render, a stable `window.location.href`, `liveSocket.isConnected() === true`, and zero exception traces in the dev server log across the click.

### 7509c453 — assign_worked_tile has no population-cap check (high)

`WorldServer.validate_assign/3` never checks `length(city.worked_tiles) < city.size` before adding a worked tile with no paired unassignment. A city can be assigned more worked tiles than its size supports, permanently over-harvesting yield — reproduces on the very first ordinary "assign a farmed tile" action (`worker_improves_the_land`'s own last step). The changeset's own `validate_worked_tiles_within_size/1` rule exists to prevent exactly this but is never invoked, since the write path uses a raw `Repo.update_all`. See `lib/broken_oaths/game/world_server.ex:1778-1814`.

### 63300098 — Settler's population cost is masked by same-tick growth (medium) — FIXED, verified 2026-07-18

`Turn.tick/1` resolves a completed settler's population cost (phase 3) and city growth (phase 5) in the same turn boundary. A city with food banked past its next growth threshold (trivially true for any long-lived, well-fed city) has the settler's pop cost silently refunded by growth in the identical tick, so city size never externally drops — defeating the intended settler/population tradeoff. Reproduces `empire_expands`'s own step-3 expectation failing to hold. See `lib/broken_oaths/game/turn.ex` (city-loop phase ordering) and `lib/broken_oaths/game/yields.ex:304-318`.

**Fix verified in the `empire_expands` re-run:** `Turn.tick/1` now tracks the set of city ids that completed a settler in the current tick and `grow_cities/2` skips growth for exactly those cities on that same tick. Stepping turns one at a time and reading `game_cities.size` via psql after every step caught the settler-completion boundary directly: size dropped 6→5 in the same step the settler spawned, then regrew to 6 on the *next* step (as expected — the skip is single-tick, not a permanent block, and this city's food surplus is well past the growth threshold). The −1 is now genuinely observable at the completion boundary, which was the entire point of the fix.

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

Original failing run (issue `b8f4ce10` evidence, kept for audit trail):
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

Re-run (fix verification, 2026-07-18):
- `.code_my_spec/qa/journeys/screenshots/j2_rerun_00_entered_world.png`
- `.code_my_spec/qa/journeys/screenshots/j2_rerun_01_bronze_spearman_selected_no_crash.png` — the crux: bronze_spearman selected, unit panel shows "Bronze Spearman", no crash
- `.code_my_spec/qa/journeys/screenshots/j2_rerun_02_city_panel_open.png`
- `.code_my_spec/qa/journeys/screenshots/j2_rerun_03_renamed_survives_reload.png`
- `.code_my_spec/qa/journeys/screenshots/j2_rerun_04_queue_two_items.png`
- `.code_my_spec/qa/journeys/screenshots/j2_rerun_05_queue_reordered.png`
- `.code_my_spec/qa/journeys/screenshots/j2_rerun_06_abandoned_current.png`
- `.code_my_spec/qa/journeys/screenshots/j2_rerun_07_turn_boundary_advanced.png`

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

Original partial run (issue `63300098` evidence, kept for audit trail):
- `.code_my_spec/qa/journeys/screenshots/j4_00_city_selected.png`
- `.code_my_spec/qa/journeys/screenshots/j4_01_settler_queued.png`
- `.code_my_spec/qa/journeys/screenshots/j4_02_settler_selected.png`
- `.code_my_spec/qa/journeys/screenshots/j4_03_too_close_toast.png`
- `.code_my_spec/qa/journeys/screenshots/j4_04_settler_arrived_far.png`
- `.code_my_spec/qa/journeys/screenshots/j4_05_second_city_founded.png`

Re-run (fix verification, 2026-07-18):
- `.code_my_spec/qa/journeys/screenshots/j4_rerun_00_settler_queued.png`
- `.code_my_spec/qa/journeys/screenshots/j4_rerun_01_size_dropped_to_5.png` — the crux: `city-size` badge reads 5 immediately after settler completion
- `.code_my_spec/qa/journeys/screenshots/j4_rerun_02_too_close_toast.png`
- `.code_my_spec/qa/journeys/screenshots/j4_rerun_03_settler_arrived_far.png`
- `.code_my_spec/qa/journeys/screenshots/j4_rerun_04_second_city_founded.png`
