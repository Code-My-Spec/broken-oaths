# Hex / globe pathfinding reference

Reference notes for unit movement and pathfinding, accumulated from the
Red Blob Games hexagon guides plus our own architecture. Use this when
touching `Unit.bfs_path/4`, `Unit.entry_cost/3`, `Terrain.movement_cost/1`,
or `Simulation.Turn.Movement`.

## External references
- Pathfinding: https://www.redblobgames.com/grids/hexagons/#pathfinding
- Implementation guide: https://www.redblobgames.com/grids/hexagons/implementation.html

## The one load-bearing takeaway
Red Blob's own words: *"pathfinding on hex grids isn't different from
pathfinding on square grids."* It is **coordinate-system-agnostic** —
standard graph algorithms (BFS for unweighted, Dijkstra for weighted
movement costs, A* with a heuristic) run over a **neighbor function**,
filtering impassable tiles. Movement costs are per-tile entry costs; for
A*, scale the distance heuristic to match the per-tile cost.

## Why only the *algorithms* port, not the coordinate math
Broken Oaths is NOT a flat axial hex grid. Per the accepted ADRs
(`hex-globe-geometry`, `game-state-persistence`) the world is a **Goldberg
polyhedron globe** (GP(f,0), ~29k tiles, 12 pentagons), and **gameplay is
graph traversal over per-tile neighbor lists** — there are no axial/cube
coordinates. So Red Blob's coordinate sections (axial math, distance
formulas, coordinate conversions) **do not apply**; only the pathfinding
*algorithm* guidance does, because it only needs a neighbor function,
which our mesh provides (`Worlds.Globe` tile `neighbors`,
`Regions.adjacent_tiles/2`).

## Our current implementation (story 925)
- `Terrain.movement_cost/1`: open terrain = 1; DIFFICULT (hills, or
  feature woods/rainforest/marsh) = 2. Mountains/water are impassable via
  tile class, not cost.
- `Unit.entry_cost/3`: a **completed road** makes a tile cost 1 regardless
  of terrain; otherwise it's `Terrain.movement_cost/1`. Single source of
  truth for both pathfinding and the movement step.
- `Unit.bfs_path/4`: weighted shortest path (**Dijkstra**, `:gb_sets`
  frontier keyed `{cost, tile_id}` so ties break by lowest tile id for
  determinism). This is exactly the "Dijkstra with movement costs" Red Blob
  recommends. Units route along roads / cheap terrain and around difficult
  terrain.
- `Turn.Movement`: resolves `:pending` move orders in lockstep rounds,
  spending `entry_cost` per step, with Civ 6's **"a unit with any movement
  may always move at least one tile"** rule (the `active_movers/1` gate is
  `movement_left > 0`, never `>= cost`, so a movement-1 unit can still enter
  a cost-2 tile and drop to 0).

## Known gaps / open decisions (do not silently change)
1. **Interrupted orders never auto-retry.** In `Turn.Movement`, a step into
   an occupied tile flips the order to `:interrupted` and it is NOT retried
   until something re-queues it (moduledoc). A unit in a clump / near
   barbarians whose path is momentarily blocked just *sits* until the
   player re-issues the order. This reads to players as "my Lord is a turn
   behind / won't move." Whether a blocked move order should auto-resume
   (or re-path) next tick when the tile clears is a **pending PM design
   decision**, not a bug to patch blindly.
2. **A\* is a future optimization.** Dijkstra is correct and fine at our
   scale; if pathfinding cost ever matters, add A* with a
   great-circle/chord distance heuristic on the unit sphere, scaled to the
   min per-tile cost (1). Keep the deterministic lowest-tile-id tie-break.

## Movement pacing note
The every-other-turn "can't move / lost a turn / fortify cost 2 turns"
reports were the **recharge split** (`recharge_turns`, default 2): movement
only recharged every 2nd tick, so a unit at 0 points was stranded on
off-turns. Fixed by the **timer inversion** — movement recharges every tick
(fast 1-min action layer); only the economy (income/production/research/
growth) runs on the slow `economy_turns` cadence. `fortify/3` itself never
costs movement.
