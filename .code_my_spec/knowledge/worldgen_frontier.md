# Worldgen Frontier — Next-Level Techniques for a Goldberg-Tile Planet

Research date: 2026-07-13. Author: research agent for broken_oaths.

**Scope.** How to push past pure 3D-Perlin worldgen on our tile-graph planet
(f=54 Goldberg: 29,162 hexes + 12 pentagons, explicit per-tile `neighbors` and
ordered `corners`, deterministic per seed, ~100 ms now, budget up to ~1–2 s).
Priority order matches the brief: **rivers first**, then tectonics, wind/rain,
currents, resources, erosion, and the functional-performance patterns that make
all of it fit in Elixir.

The single most important framing: **our mesh is already the exact data
structure these algorithms want.** Amit Patel's mapgen4 river code "didn't
require any changes to work on spheres… because the underlying structure was
graph-based" ([Red Blob, planet generation](https://www.redblobgames.com/x/1843-planet-generation/)).
We have a graph of 29k nodes with adjacency and dual corners. Every technique
below is a graph pass, not a raster pass — no lat/lon, no seams.

---

## 0. Two graphs, one mesh (the enabling insight)

Our tiles form **two dual graphs**, and rivers need both:

- **Tile graph** (what we have): nodes = tile centers, edges = `neighbors`.
  ~29k nodes, ~87k edges. Good for tile-based flow, plates, wind, biomes.
- **Corner graph** (must be built once): nodes = the shared corners (dual
  vertices). On a Goldberg polyhedron every corner is **trivalent** — shared by
  exactly 3 tiles — so each corner connects to exactly 3 other corners along the
  3 tile-tile edges meeting there. Count = `20f²` corners (58,320 for f=54),
  `30f²` corner-edges (87,480). **Each corner-edge is exactly one tile-tile
  boundary.** This is the structure Civ-style *edge rivers* run on: a river
  segment is a corner→corner hop, which is geometrically the border between two
  adjacent tiles.

Building the corner graph: our tiles already store `corners` as ordered
coordinate rings. Dedupe corners into stable integer ids (three tiles report the
same corner point — key by rounded coordinate or, better, by the topological
triangle-id from mesh construction), then for each corner record its 3 neighbor
corners and the 3 tiles around it. One-time O(tiles) pass. This is the
sphere-analog of mapgen2's "corners" (blue points) vs "centers" (red points)
([Amit, Polygonal Map Generation](https://www.redblobgames.com/maps/mapgen2/)).

**Decision you must make for rivers (Section 1):** do rivers live on *tiles*
(Azgaar/DF style — a tile "is" river) or on *edges* (Civ/mapgen2 style — a tile
"has a river on its SW edge, but the tile itself is dry farmland")? The brief
asks for Civ-style edge rivers, so the corner graph is the target. I detail both
because the tile version is a strictly easier first increment.

---

## 1. RIVERS (top priority)

Real rivers are not noise — they are the **solution to a flow problem on a
height graph**. Every credible generator (mapgen2, mapgen4, Azgaar, Dwarf
Fortress, Undiscovered Worlds) does the same three-stage pipeline. Only the
data structure differs.

### 1.1 The universal pipeline

1. **Fill depressions** so every land node has a downhill path to the sea
   (else water pools in noise pits and never reaches the ocean).
2. **Assign a downhill pointer** per node → this turns the graph into a forest
   of trees rooted at the ocean (the drainage tree / flow tree).
3. **Accumulate flow**: pour rainfall into every node and sum it downstream;
   discharge at a node = rainfall of its whole upstream catchment. River width
   ∝ discharge. Draw where discharge exceeds a threshold.

Everything else (lakes, meanders, tributaries) falls out of these three.

### 1.2 Stage 1 — Depression filling on a graph (Priority-Flood)

**Use the Priority-Flood algorithm (Barnes, Lehman & Mulla 2014).** It was
written for raster DEMs but is defined on an arbitrary graph and is the modern
standard — it "outperforms the methods of Jenson–Domingue and Planchon–Darboux
in both time complexity and memory," is ~20 lines of pseudocode, and runs in
O(n) for integer heights or O(n log n) with a priority queue
([Barnes et al., arXiv:1511.04463](https://arxiv.org/pdf/1511.04463);
[ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0098300413001337)).
Azgaar's `resolveDepressions()` is exactly this step
([Azgaar rivers](https://azgaar.wordpress.com/2017/05/08/river-systems/)).

Graph version, adapted to our tiles:

```
# Input: elevation[tile], set of ocean/border tiles
# Output: filled[tile] such that every land tile drains to ocean
PriorityFlood(elevation, ocean_tiles):
  filled = copy(elevation)
  pq = min-priority-queue keyed by filled-height
  closed = bitset
  for t in ocean_tiles:           # seed from the sea
    push(pq, t, elevation[t]); closed[t] = true
  while pq not empty:
    (c, h) = pop_min(pq)          # lowest unprocessed frontier tile
    for n in neighbors(c):
      if closed[n]: continue
      # raise n to at least c's level (+epsilon for a gradient)
      filled[n] = max(elevation[n], h + eps)
      closed[n] = true
      push(pq, n, filled[n])
  return filled
```

- Flooding inward from the ocean guarantees each tile is assigned the lowest
  spill height on its path to the sea. Pits get raised to their pour point.
- `eps` (a tiny per-step increment) gives every filled cell a defined downhill
  gradient — this is the one nice property of **Planchon–Darboux** (each cell
  ends with a defined flow direction), and adding `eps` folds it into
  Priority-Flood ([Planchon–Darboux variant](https://www.researchgate.net/publication/332148339)).
- Where you *want* a lake instead of a filled flat, record cells whose fill was
  large (fill − original > threshold) as **lake tiles** rather than land; Azgaar
  forms lakes exactly here ("when depressions cannot be resolved, lakes form").
- Cost at 29k tiles with a pairing/binary heap: sub-10 ms. This is cheap.

**Alternative — carving instead of filling.** Dwarf Fortress "carves channels in
the elevation field" so fake rivers from mountains find the sea
([DF wiki, world generation](https://dwarffortresswiki.org/index.php/DF2014:World_generation)).
Carving looks more incised but mutates terrain; filling is simpler and
non-destructive. **Recommend fill.**

### 1.3 Stage 2 — Downhill pointers → the flow tree

After filling, for each land tile pick the neighbor with the lowest filled
height as its `downhill[tile]`. Ocean/lake tiles are roots. Because filling
removed all pits, following `downhill` from any land tile terminates at the sea:
the pointers form a **spanning forest of trees rooted at the ocean**. Two
streams can merge (a tile can be the downhill target of several neighbors =
**confluence**) but a tile has exactly one downhill target, so **a river never
splits** — exactly mapgen4's invariant
([Blobs in Games, mapgen4 rivers](https://simblob.blogspot.com/2018/10/mapgen4-river-representation.html)).

For **edge rivers** (Civ style), do this on the **corner graph** instead: assign
each corner an elevation (min or mean of its 3 surrounding tiles), fill
depressions on the corner graph, and give each corner a downhill *corner*. A
river is then a path of corner→corner hops, and each hop's tile-tile boundary is
the edge that "has a river." This is precisely mapgen2: "rivers flow through
corner-to-corner edges," where each such edge is the border between two polygons
([Amit, Polygonal Map Generation](https://www.redblobgames.com/maps/mapgen2/)).

### 1.4 Stage 3 — Flow accumulation (the trick that makes it fast)

mapgen4's key idea: **store the flow tree as an array in BFS order (parents
before children) plus a parallel `parent[]` int array.** Then flow accumulation
is one reverse loop — no recursion, no pointer chasing, cache-friendly, trivial
in a functional language because it's a fold over an ordered list
([mapgen4 river representation](https://simblob.blogspot.com/2018/10/mapgen4-river-representation.html)):

```
# order = tiles in BFS order from ocean roots outward (parents first)
# parent[t] = downhill target of t
FlowAccumulation(order, parent, rainfall):
  flow = zeros
  for t in reverse(order):        # leaves (springs) first, roots last
    flow[t] += rainfall[t]
    flow[parent[t]] += flow[t]    # push my whole catchment downstream
  return flow
```

`flow[t]` is now the discharge = summed rainfall of the entire upstream
catchment. **River width/segment visibility ∝ sqrt(flow)** (Azgaar and mapgen2
both scale width with accumulated flux; sqrt because width ∝ √discharge
physically). Draw a river on every corner-edge (edge model) or mark every tile
(tile model) whose `flow` exceeds a threshold; the threshold controls river
density.

- `rainfall[t]` should come from the **precipitation model (Section 3)**, not a
  constant — that's what makes wet mountains spawn big rivers and deserts spawn
  none. Until Section 3 lands, uniform rainfall + elevation still gives
  believable dendritic networks.
- Tributaries and confluences are automatic (tree structure). Meandering is
  cosmetic: offset each drawn corner slightly along the tangent, or subdivide
  the corner→corner segment with a jittered midpoint. Nick McDonald's meandering
  work is far heavier than we need
  ([nickmcd.me meandering rivers](https://nickmcd.me/2023/12/12/meandering-rivers-in-particle-based-hydraulic-erosion-simulations/)).

### 1.5 Recommended river design for broken_oaths

- **Model:** edge rivers on the **corner graph** (Civ feel, matches the brief;
  tiles stay usable farmland with a river on one edge). Build the corner graph
  once (Section 0).
- **Pipeline:** corner elevations → Priority-Flood fill (lakes where fill is
  deep) → downhill corner pointers → BFS-order array → reverse-fold flow
  accumulation → threshold + sqrt-width for drawing.
- **Cost:** all four passes are O(tiles) or O(tiles log tiles); comfortably
  <50 ms total at 29k. This is the highest payoff feature in the whole report.
- **Cheaper first increment if edge rivers are too much rendering work:** do the
  identical pipeline on the **tile graph** and mark whole tiles as `river`
  feature. Ships in a day; upgrade to edge rivers later without changing the
  algorithm.

---

## 2. TECTONICS-LITE (believable continents & ranges)

Pure fBm gives blobby, self-similar coastlines with mountains scattered by
elevation threshold. Plates give **linear mountain arcs, matching coastlines,
and ocean trenches** — the things noise can't. Red Blob's one-week planet used a
deliberately cheap version and it already beats noise
([Red Blob planet generation](https://www.redblobgames.com/x/1843-planet-generation/)).

### 2.1 Assign plates by random flood-fill

1. Pick N seed tiles (N ≈ 10–40; ~20 reads well on a sphere).
2. **Random-fill** from the seeds: like BFS but pop a *random* frontier element
   instead of FIFO/LIFO. This yields irregular, natural plate boundaries;
   plain BFS gives unnaturally round plates
   ([Red Blob](https://www.redblobgames.com/x/1843-planet-generation/)). Store
   `plate[tile]` in a flat int array.
3. Tag each plate ocean or continental (a per-plate random threshold; ~40–55%
   continental looks Earth-like).

Refinements the community found worth it: farthest-point seed placement so
plates are evenly spread, a compactness penalty to avoid spindly plates, and
grouping same-type plates into ~20 "super-plates" for broad orogenic belts
([planet_heightmap_generation](https://github.com/raguilar011095/planet_heightmap_generation),
[World Orogen](https://www.orogen.studio/)).

### 2.2 Assign motion and classify boundaries

Give each plate a **motion vector** — pick a random rotation axis/Euler pole and
a small angular speed; a tile's velocity is `ω × position` (great-circle
motion, not a flat 2D vector — we're on a sphere). At every tile-tile edge where
the two tiles belong to different plates, compute the **relative approach speed**
along the edge normal (Red Blob uses Δdistance between the two tiles' next
positions; more negative = converging):

| Boundary | Converging (Δ < −t) | Otherwise / diverging |
|---|---|---|
| continental + continental | mountain range (uplift) | rift valley |
| continental + ocean | coastal mountains + trench (subduction) | passive coast |
| ocean + ocean | island arc / ridge | mid-ocean ridge (divergent) |

(Table adapted from Red Blob's land/ocean × Δdistance rules
([1843](https://www.redblobgames.com/x/1843-planet-generation/)); the threshold
`t` prevents "over-mountainization," a bug Red Blob explicitly hit.)

### 2.3 Turn boundaries into elevation (distance fields)

Mark boundary tiles as uplift (mountain), trench, or ridge, then **interpolate
elevation across plate interiors via distance fields**: BFS-distance from each
tile to the nearest mountain boundary, to the nearest coast, and to the nearest
ocean, then combine (Red Blob uses three distance fields; the community version
uses a harmonic mean of mountain/ocean/coast distances with asymmetric mountain
profiles)
([1843](https://www.redblobgames.com/x/1843-planet-generation/),
[planet_heightmap_generation](https://github.com/raguilar011095/planet_heightmap_generation)).
Multi-source BFS over 29k tiles is a few ms.

**Recommended hybrid:** use tectonics for the **macro** elevation skeleton
(continent shapes, mountain arcs, trenches) and **add your existing fBm as a
high-frequency detail layer** on top (`elev = 0.7*tectonic + 0.3*fbm_detail`).
This keeps organic coastlines while gaining structure. This is strictly better
than either alone and reuses all your noise code.

**Caution:** Red Blob calls his plate-motion code "buggy" and admits he tuned
parameters around the bugs. Budget iteration time; get the Δdistance sign and
threshold right early or you'll fight it.

---

## 3. WIND + PRECIPITATION (kills the noise-moisture problem)

Our current moisture is independent Perlin noise — deserts and rainforests land
randomly. A tiny advection model instead produces **rain shadows**: wet windward
slopes, dry leeward interiors. This is the second-highest-payoff climate change
after rivers, and it feeds rainfall into the river model (Section 1.4).

### 3.1 Prevailing winds by latitude band

Earth's three-cell structure gives alternating bands. Assign each tile a wind
direction from its latitude (`z` = sin lat is already in our data):

- 0°–30°: **trade winds**, blowing east→west (toward the equator).
- 30°–60°: **westerlies**, west→east.
- 60°–90°: **polar easterlies**, east→west.

Even a single global prevailing direction (Azgaar's default) already produces
convincing rain shadows; the 3-band version adds realism cheaply.

### 3.2 Moisture advection with orographic rain-out

Azgaar's model, adapted to the tile graph
([Azgaar precipitation](https://azgaar.wordpress.com/2017/06/30/biomes-generation-and-rendering/),
[river systems](https://azgaar.wordpress.com/2017/05/08/river-systems/)):

1. Seed "cloud" moisture at ocean tiles (sun evaporates water off the sea).
2. **March moisture downwind across the tile graph.** For each tile in
   wind-order (sort tiles by position along the wind direction so upwind is
   processed first), pass a fraction of its moisture to its downwind neighbor.
3. **Rain out on the way:** each land tile precipitates a share of the moisture
   passing through it (that share = its `rainfall`, fed to rivers). Precipitate
   *more* on **windward uphill** steps — orographic lift: `rain += k *
   max(0, elev_here − elev_upwind)`. Dwarf Fortress models exactly this: moist
   ocean air rises over rising terrain, rains on the seaward side, and "when the
   breeze goes over the top there's no moisture left," making a leeward desert
   ([DF world generation](https://dwarffortresswiki.org/index.php/DF2014:World_generation)).
4. When moisture hits a mountain it can dump most of its remaining water and
   effectively stop (Azgaar: "when facing mountains, clouds disappear giving all
   moisture to the land").
5. If you support multiple prevailing winds, run the pass once per wind and
   average.

The march is a single sweep in wind-sorted order — O(tiles log tiles) for the
sort, O(tiles) for the sweep. One pass; no iteration to convergence needed.

**Result:** moisture is now *causal* — leeward of every range is dry, coasts and
windward slopes are wet — and it drives both biome selection (replace the noise
`moisture` in `Generator.classify/4`) and river discharge. This is a
Whittaker-lite biome ladder just like now, but with physically-placed inputs.

---

## 4. OCEAN CURRENTS + TEMPERATURE MODERATION (cheapest useful pass)

Full ocean circulation models are 3-D GCMs — massively out of scope
([ocean circulation overview](https://oceanecology.ca/wp/2015/09/08/ocean_circulation/)).
The cheap, high-value approximations:

- **Latitudinal baseline + continentality.** You already have
  `warmth = 1 − |z|·… − altitude chill`. Add a **continentality** term: interior
  tiles (large BFS-distance-to-coast) have *more extreme* temperature (hotter
  summers/colder winters → for a single value, push toward the seasonal extreme
  or simply widen the band), coastal tiles are moderated toward the ocean mean.
  One BFS distance field (reuse the coast distance from Section 2.3) → a few ms.
- **Warm/cold current hint (optional).** Approximate western-boundary warm
  currents by nudging temperature up on the *east* coasts of oceans in the
  subtropics and down on *west* coasts (or just: poleward-flowing water on
  western ocean edges carries warmth). This is a per-coastal-tile lookup, not a
  simulation. It's the difference that makes "why is Britain warm at that
  latitude" work. Low priority; do it only if temperature bands look too zonal.

**Recommendation:** ship continentality (it visibly improves interior deserts
and tempers coasts and reuses the coast distance field); treat directional
currents as a nice-to-have polish item.

---

## 5. RESOURCE / FEATURE PLACEMENT

Model on Civ's `AssignStartingPlots` design
([CivFanatics map-script guide](https://forums.civfanatics.com/threads/guide-map-scripts.637015/),
[Steam discussion](https://steamcommunity.com/app/8930/discussions/0/617336568066080607/)):

- **Terrain-adjusted, civ-agnostic strategic/bonus resources.** Strategics
  (iron/horses/oil analogs) are placed by terrain/feature eligibility *without
  knowledge of who's playing* — a filter pass over tiles + weighted random.
- **Clustered deposits via impact radius.** Civ's `ProcessResourceList` drops a
  major deposit on an eligible tile, then places a **randomized radius of
  impact** (min–max) so resources appear in believable clusters, not uniform
  scatter. On our graph: pick seed tiles by weight, then BFS out a random
  1–3 ring depositing with decaying probability. Clustering > pure scatter for
  strategics; luxuries can be single rare tiles.
- **Fairness via minimum spacing.** Reuse your existing `find_spawn_points`
  spread logic (max-min chord distance) — Civ enforces min start distances
  (major–major 9, major–minor 7) and penalizes viability within an 8-tile radius
  of chosen starts. For a symmetric-feeling map, place a comparable resource
  cluster near each spawn (the "strategic balance" option).
- **Luxuries near starts, strategics globally.** Civ places luxuries relative to
  start locations, strategics/bonus across the whole map outside start rings.

This is all cheap filter + BFS-ring work, O(tiles); it depends on rivers,
tectonics, and climate being in place first (resources should follow terrain).

---

## 6. EROSION ON THE TILE GRAPH — mostly SKIP

Particle-based hydraulic erosion (drop raindrops, carry sediment downslope,
deposit) is beautiful on **heightfield grids**
([Nick McDonald](https://nickmcd.me/2020/04/10/simple-particle-based-hydraulic-erosion/),
[Job Talle](https://jobtalle.com/simulating_hydraulic_erosion.html)), but:

- It's designed for dense rasters where a particle slides continuously; on a 29k
  irregular graph a particle hops tile-to-tile and the visual payoff (fine
  valley incision, dunes) is below our tile resolution — you can't see sub-tile
  gullies.
- It needs thousands of particles × many steps, mutating shared height — the
  worst fit for immutable Elixir (Section 7).
- **The river pipeline already gives you the 80%:** Priority-Flood + flow
  accumulation *is* drainage. If you want incision, do one cheap
  **flow-proportional carve**: lower each tile's elevation by `k *
  sqrt(flow[t])` after accumulation (high-discharge tiles sit lower → valleys).
  That's a single O(tiles) pass, deterministic, no particles.
- **Thermal erosion** (talus: repeatedly move material from steep to lower
  neighbors until slope < angle of repose) is graph-friendly and cheap if you
  want to soften mountain spikes — a handful of relaxation passes over the tile
  graph. Optional polish.

**Verdict:** skip particle hydraulic erosion. Use the free drainage from rivers,
plus optionally one flow-carve pass and/or a few thermal-relaxation passes.

---

## 7. DETERMINISM + PERFORMANCE IN ELIXIR

All passes must stay deterministic per seed and fit ~1–2 s for 29k tiles.

**Two pass shapes, two strategies:**

- **Embarrassingly parallel, per-tile** (noise sampling, biome classification,
  wind-independent fields): `Task.async_stream/3` over tiles, ordered results
  reassembled deterministically. This is what your generator already does and it
  scales across cores.
- **Inherently sequential graph passes** (Priority-Flood, flow accumulation,
  wind advection, distance-field BFS): these have data dependencies and must run
  single-threaded, but they're O(tiles)–O(tiles log tiles) and cheap. Make them
  fast, not parallel.

**Concrete Elixir patterns:**

- **Use `:array` or (better) a large tuple / binary indexed by tile id, not a
  map, for the hot inner arrays** (`elevation`, `filled`, `flow`, `plate`,
  `downhill`, `parent`). Map update/lookup is O(log n) with allocation churn;
  for flow accumulation over 29k nodes that dominates. mapgen4's whole point is
  *flat arrays in BFS order* — mirror that. In Elixir a **tuple with
  `elem/2`/`put_elem/2`** or `:array` gives O(1)-ish access; for the reverse-fold
  accumulation you can also just fold over a pre-sorted list carrying an
  accumulator map only for the changing frontier.
- **`:ets` for genuinely mutable accumulation** if tuple copying is too slow:
  an ETS table keyed by tile id with `:set` and `update_counter` makes flow
  accumulation and priority-flood in-place and fast, while staying inside one
  process (determinism preserved). This is the pragmatic escape hatch for the
  sequential passes.
- **Priority queue:** use a pairing heap / `:gb_trees` for Priority-Flood's PQ.
  ~29k pushes/pops is nothing.
- **Determinism:** every stochastic choice (plate seeds, motion axes, resource
  jitter, random-fill pops) must draw from a **seeded PRNG threaded explicitly**
  (`:rand` with `:rand.seed(:exsss, {a,b,c})` from the world seed, or carry a
  splittable seed). Sort any set you iterate (tile ids, frontier ties) so
  ordering never depends on map traversal order. You already do this for spawn
  selection.
- **Budget sketch (29k tiles, single core unless noted):** noise elevation +
  moisture (parallel) ~100 ms (current); Priority-Flood ~5–15 ms; downhill +
  BFS-order + flow accumulation ~5–10 ms; plate flood-fill + distance fields
  ~10–30 ms; wind advection sweep ~10–20 ms; resource placement ~5 ms. **Total
  well under 300 ms** even before parallelism — the 1–2 s budget is generous.
- **Cache the mesh + corner graph.** They're seed-independent; build once at
  boot (you already warm textures at boot), so per-world cost is only the
  seeded passes.

---

## 8. RANKED IMPLEMENTATION ROADMAP (effort × payoff)

Ordered by payoff-per-unit-effort. Each step is independently shippable and
deterministic.

| # | Feature | Effort | Payoff | Notes / dependencies |
|---|---|---|---|---|
| **1** | **Rivers, tile-based** (Priority-Flood → downhill → flow accumulation, mark river tiles) | **M** | **Very high** | Biggest single visual/gameplay win. Uniform rainfall is fine to start. Reuses tile graph only. |
| **2** | **Tectonics-lite** (random-fill plates → boundary classify → distance-field elevation, blended 70/30 with existing fBm) | M–L | High | Fixes blobby continents & scattered mountains; gives rivers real ranges to drain. Watch the Δdistance threshold. |
| **3** | **Wind + orographic precipitation** (latitude winds → moisture advection sweep) | M | High | Replaces noise-moisture in `classify/4`; feeds real `rainfall` into rivers (upgrades step 1 for free). Do after tectonics so mountains exist to cast shadows. |
| **4** | **Edge rivers on the corner graph** (upgrade step 1 to Civ-style boundary rivers) | M | High | Build corner graph once; same algorithm, better feel + keeps tiles farmable. Do once tile rivers prove out. |
| **5** | **Continentality temperature** (coast distance field widens interior extremes, tempers coasts) | S | Medium | One BFS reuse; noticeably better interior deserts/tempered coasts. |
| **6** | **Resource placement** (terrain-filtered strategics with impact-radius clusters + fairness spacing) | S–M | Medium | Needs 1–3 done first (resources follow terrain/climate). Reuse `find_spawn_points` spread logic. |
| **7** | **Thermal-relaxation + flow-carve polish** (soften peaks, incise high-discharge valleys) | S | Low–Med | Cheap graph passes; do only if terrain reads too spiky/flat. |
| **8** | **Directional ocean currents** (warm/cold coast nudges) | S | Low | Only if temperature bands look too zonal. |
| — | Particle hydraulic erosion | L | Low (at this res) | **Skip.** Drainage from step 1 already covers it. |

**One-line thesis:** rivers, tectonics, and orographic rain (steps 1–3) are the
three passes that convert a noise planet into a *believable* one; they're all
cheap graph algorithms on the mesh we already have, they compose (tectonics
makes mountains, wind makes rain shadows on them, rivers drain the rain), and
together they fit in a few hundred milliseconds.

---

## Sources

- Amit Patel / Red Blob Games — Procedural map generation on a sphere:
  https://www.redblobgames.com/x/1843-planet-generation/
- Amit Patel — Polygonal Map Generation for Games (corner/center graph, rivers,
  biomes): https://www.redblobgames.com/maps/mapgen2/ and the 2010 article
- Amit Patel — Mapgen4: https://www.redblobgames.com/maps/mapgen4/
- Blobs in Games — Mapgen4 river representation (flow tree, BFS array, reverse
  accumulation): https://simblob.blogspot.com/2018/10/mapgen4-river-representation.html
- Barnes, Lehman & Mulla — Priority-Flood depression filling/watershed labeling:
  https://arxiv.org/pdf/1511.04463 ·
  https://www.sciencedirect.com/science/article/abs/pii/S0098300413001337
- Planchon–Darboux variant (per-cell gradients):
  https://www.researchgate.net/publication/332148339
- Azgaar — River systems: https://azgaar.wordpress.com/2017/05/08/river-systems/
- Azgaar — Biomes generation and precipitation/wind model:
  https://azgaar.wordpress.com/2017/06/30/biomes-generation-and-rendering/
- Azgaar Fantasy Map Generator — rivers & water features (DeepWiki):
  https://deepwiki.com/Azgaar/Fantasy-Map-Generator/2.2-rivers-and-water-features
- Dwarf Fortress Wiki — World generation (rain shadow, drainage, river carving):
  https://dwarffortresswiki.org/index.php/DF2014:World_generation ·
  https://dwarffortresswiki.org/index.php/DF2014:Advanced_world_generation
- Procedural planet w/ tectonics, distance-field elevation:
  https://github.com/raguilar011095/planet_heightmap_generation ·
  World Orogen: https://www.orogen.studio/
- Civ V/VI resource & start placement (AssignStartingPlots, impact radius,
  fairness): https://forums.civfanatics.com/threads/guide-map-scripts.637015/ ·
  https://steamcommunity.com/app/8930/discussions/0/617336568066080607/
- Nick McDonald — particle hydraulic erosion / hydrology / meandering rivers:
  https://nickmcd.me/2020/04/10/simple-particle-based-hydraulic-erosion/ ·
  https://nickmcd.me/2020/04/15/procedural-hydrology/ ·
  https://nickmcd.me/2023/12/12/meandering-rivers-in-particle-based-hydraulic-erosion-simulations/
- Job Talle — Simulating hydraulic erosion:
  https://jobtalle.com/simulating_hydraulic_erosion.html
- Ocean circulation model overview (why full sim is out of scope):
  https://oceanecology.ca/wp/2015/09/08/ocean_circulation/
</content>
</invoke>
