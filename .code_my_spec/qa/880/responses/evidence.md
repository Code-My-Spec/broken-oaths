# Story 880 — City Growth — raw evidence transcripts

## 7474 / 7475 — live size-1 -> size-2 transition (city 5, world 6, player 12 "qa880-fresh")

Founded via REAL `[data-test='found-city']` button click (not the liveSocket
hook workaround — see below):

```
psql> SELECT id, player_id, tile_id, name, size, food, territory FROM game_cities WHERE player_id=12;
 id | player_id | tile_id |  name  | size | food |              territory
----+-----------+---------+--------+------+------+---------------------------------------
  5 |        12 |    8083 | City 1 |    1 |    0 | {8041,8042,8082,8083,8084,8123,8124}
```

Food polled across turn boundaries (turn 2569 at founding -> turn 2576 at growth):

```
turn 2572: food=4
turn 2575: food=16
turn 2576: food=20 -> GROWTH FIRED
```

Post-growth snapshot:

```
psql> SELECT id, size, food, territory, worked_tiles FROM game_cities WHERE id=5;
 id | size | food |                 territory                 | worked_tiles
----+------+------+-------------------------------------------+--------------
  5 |    2 |    0 | {8041,8042,8082,8083,8084,8123,8124,8085}  | {8124,8085}
```

- Territory gained exactly one tile: `8085` (7 -> 8 tiles).
- Predicted via pure `Yields.pick_growth_tile/3` probe BEFORE the boundary
  fired: `8085` — exact match against what the live tick actually claimed.
- Food went 16 -> 20 (threshold reached) -> settled to 0 (16 + 4/turn accrual
  - 20 threshold = 0 exact remainder; not a bug, just an exact multiple).
- worked_tiles gained a second entry (`8085`, auto-assigned to the new
  citizen) — same tick as growth.
- UI (`[data-test='city-panel']`) confirmed: `city-size` = "2",
  `city-food` = "6/30" a few seconds later (one more turn's accrual on top
  of the post-growth 0), threshold correctly reads 30 for size 2
  (`Yields.threshold(2) == 30`).

## 7476 — worked tiles per citizen

- Size-1 founding: `worked_tiles = [8124]` (1 tile, auto-assigned at
  founding via `persist_found_city!`/`Yields.pick_worked_tile/2`).
- Size-2 post-growth: `worked_tiles = [8124, 8085]` (2 tiles).
- Center tile `8083` never appears in `worked_tiles`, rendered separately
  as "Free" in the UI.
- Manual reassignment exercised live: clicked real "Unwork" button on tile
  8085 (`[data-test='city-worked-tile-8085'] button`) -> DB confirmed
  `worked_tiles = [8124]`. Clicked real "Work" button on tile 8041
  (`button[phx-value-to_tile_id='8041']` — note: assignable-tile rows have
  NO `data-test`, see issue 306851c6) -> DB confirmed
  `worked_tiles = [8124, 8041]`.
- Secondary read-only corroboration across existing cities (not mutated):
  - World-1 city 4 (QA user), size 3 -> `worked_tiles` has exactly 3
    entries: `{6483,6484,6527}`.
  - World-6 Oakhaven (city 1), size 4 -> `worked_tiles` has exactly 4
    entries: `{21634,21607,21578,21606}`.

## 7477 — size-4 cap (Oakhaven, city 1, world 6) — read-only, untouched

Food polled at 4 points across this session (turn ~2565 -> ~2578, wall time
~13 min), size unchanged at 4 throughout:

```
food=470 (brief-writing time)
food=530
food=540
food=590
```

Pure-function confirmation (`BrokenOaths.Game.Yields`, no GenServer/Repo):

```
threshold(1) => 20
threshold(2) => 30
threshold(3) => 40
threshold(4) => nil
capped?(3)   => false
capped?(4)   => true
```

UI confirmed: `[data-test='city-size']` = "4",
`[data-test='city-food']` text = "540/Capped" (exact `food_label(nil)`
output from `city_panel.ex`), 4 worked-tile rows present with "Unwork"
buttons.

Code path: `Turn.tick/1` runs `accrue_food/1` unconditionally every tick
(before the growth phase), while `grow_cities/1` calls `Yields.grow/3`,
which short-circuits to a no-op when `threshold(city.size)` is `nil`
(size >= 4) — food keeps banking every turn, growth simply never re-fires.
No crash, no data loss (city row well-formed, lord unit present) at any
point observed.

## 7490 — yield stacking

Direct pure-function calls with the exact terrain combinations named in
criterion 7490 (`BrokenOaths.Game.Yields.tile_yield/1`,
`city_center_yield/1` — no world/DB needed, same functions the live tick
calls):

```
grassland+hills+woods -> %{food: 2, production: 2}
flat desert            -> %{food: 0, production: 0}
snow (city-center floor) -> %{food: 2, production: 1}  (raw snow yield %{food:0,production:0} floored)
```

These match the BDD spec's exact assertions
(`criterion_7490_..._spex.exs`: `hw_food_delta == 2`, `hw_prod_delta == 2`,
`desert_food_delta == 0`, `desert_prod_delta == 0`, `snow_food_per_turn ==
2`) exactly.

Exhaustive scan for a live, reachable grassland+hills+woods tile:

```
world 1  ("Jade Wilds", freq 54, 29162 tiles): 10 matches, e.g. tile 14062
  (lat ~13.9, lon ~-19.8) — city 4's territory is at lat ~74.7, lon ~-55.9,
  opposite side of the globe, unreachable in any practical time-box.
world 6  ("QA World", freq 54, 29162 tiles, seed 424242): 0 matches
  (confirms the BDD spec's own comment that seed 424242 has none).
world 10 ("QA World (Fill Test)", freq 8, 642 tiles): 1 match, tile 328
  (lat ~71.9, lon ~51.0) — also far from both existing cities there.
world 6 additionally scanned for ANY :hills-relief tile at all: 0 matches
  world-wide (not just near cities) — this seed generates no hills terrain.
```

Partial live corroboration via real, DB-backed worked tiles reached this
session (2 of 3 additive components each, via `Regions.terrain/2` +
`Yields.tile_yield/1` against actual world data):

```
tile 8124 (world 6, city 5's worked tile): plains+flat+rainforest
  -> %{food: 2, production: 1} = base{1,1} + rainforest(+1 food).
tile 640 / 617 (world 10, other players' cities, read-only):
  grassland+flat+woods -> %{food: 2, production: 1} = base{2,0} + woods(+1 prod).
tile 616 (world 10): tundra+flat+woods -> %{food: 1, production: 1}.
```

No live-reachable tile combines all three (base+relief+feature) at once in
either world touched this session — the full 3-way stack is code-verified
only (direct pure-function call with the criterion's exact terrain), not
observed through a live UI/DB flow end-to-end.

## found_city real-button re-verification

Real `[data-test='found-city']` button (in `GameLive.UnitPanel`) clicked
directly (no liveSocket hook) for the new throwaway account's settler
(unit 29, world 6): succeeded on the first try. `game_cities` row created
immediately, settler consumed from `game_units`, no `city-error` element
rendered. This corroborates issue `ee6f7ccb-352d-4948-81aa-c3669f9cc2d9`'s
open question — as of this session (dev server not restarted since 879),
the real button now works for `found_city` too.
