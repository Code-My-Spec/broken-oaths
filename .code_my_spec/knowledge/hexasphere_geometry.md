# Hex-Tiled Sphere (Hexasphere / Goldberg Polyhedron) — Research Report

Research date: 2026-07-12. Basis for the hex-globe conversion.

## 0. TL;DR / Recommendation

- Build a **Class I Goldberg polyhedron `GP(f,0)`** by subdividing an icosahedron `f` times, projecting to the sphere, and taking the **dual** (triangle centroids become tile corners; original + subdivided vertices become tile centers).
- **Tiles = `10f² + 2`**, always exactly **12 pentagons** and `10(f²−1)` hexagons.
- To match the old 200×150 = 30,000 flat tiles, use **`f = 55` → 30,252 tiles** (or `f = 54` → 29,162). [Chosen: f=54.]
- For Elixir server-side generation: **build the dual mesh explicitly once and store an adjacency list keyed by integer tile id**. Do not try to keep a global axial coordinate — none exists on a sphere.
- Orient the icosahedron **vertex-up**: one pentagon at each pole, plus a ring of 5 pentagons at **+atan(1/2) ≈ +26.565°** and another 5 at **−26.565°** latitude, the two rings offset by 36° in longitude.
- Terrain: sample **3D simplex/Perlin fBm at each tile's unit-sphere center `(x,y,z)`** → inherently seamless.
- Pathfinding: **BFS/A\* over the adjacency graph**, using **great-circle distance between tile centers** as the A\* heuristic.

## 1. Goldberg polyhedron `GP(m,n)` and tile-count scaling

A Goldberg polyhedron is the dual of a geodesic (subdivided icosahedron) polyhedron. It has only pentagon and hexagon faces, exactly 3 faces meet at every vertex, and it has full icosahedral symmetry. Euler's formula forces **exactly 12 pentagons** regardless of size.

**Triangulation number:**
```
T = m² + m·n + n²      (equivalently (m+n)² − m·n)
```

**Counts for the icosahedral Goldberg polyhedron `GP(m,n)`** (these are the *faces = game tiles*):

| Quantity | Formula |
|---|---|
| Faces (**tiles**) | `10·T + 2` |
| Pentagons | `12` (always) |
| Hexagons | `10·(T − 1)` |
| Vertices (tile **corners**) | `20·T` |
| Edges (tile-tile **adjacencies**) | `30·T` |

**Classes:**
- **Class I** `GP(n,0)`: `T = n²`. Aligned, symmetric, "straight" rows. **The usual choice** (hexasphere.js and most game generators).
- **Class II** `GP(n,n)`: `T = 3n²`. (e.g. `GP(1,1)` = the truncated icosahedron / soccer ball.)
- **Class III** `GP(m,n)`, `m≠n`, both ≠0: chiral / skewed.

**Use Class I `GP(f,0)`**, so `T = f²` and **tiles = `10f² + 2`**, where `f` = number of segments each icosahedron edge is cut into (the "frequency" / `subDivisions`).

**Tile counts vs. frequency (Class I):**

| `f` | Tiles `10f²+2` | Hexagons `10(f²−1)` | Corners `20f²` | Adjacencies `30f²` |
|----:|----:|----:|----:|----:|
| 8  | 642    | 630    | 1,280  | 1,920 |
| 16 | 2,562  | 2,550  | 5,120  | 7,680 |
| 24 | 5,762  | 5,750  | 11,520 | 17,280 |
| 32 | 10,242 | 10,230 | 20,480 | 30,720 |
| 40 | 16,002 | 15,990 | 32,000 | 48,000 |
| 48 | 23,042 | 23,030 | 46,080 | 69,120 |
| **54** | **29,162** | 29,150 | 58,320 | 87,480 |
| **55** | **30,252** | 30,240 | 60,500 | 90,750 |
| 56 | 31,362 | 31,350 | 62,720 | 94,080 |
| 64 | 40,962 | 40,950 | 81,920 | 122,880 |

**Note on power-of-two subdivision:** recursive 4-way triangle splitting only gives `f = 2^k` frequencies. Cutting each edge into `f` equal parts directly (hexasphere.js's `subDivisions`) allows **any integer `f`** — needed for f=54/55.

Cross-check on adjacency count: `(12·5 + (10f²−10)·6) / 2 = 30f²`. ✓

## 2. Tile addressing / data model — comparison and recommendation

### (a) Icosahedral / barycentric per-face addressing
Address a tile as `(face 0..19, i, j)` within that triangular face's sub-grid (what ISEA/DGGRID/H3/rHEALPix effectively do).
- **Pros:** compact, hierarchical, O(1) index math in face interior, equal-area options.
- **Cons:** **seam stitching** is the hard part — tiles on the 30 shared edges and 12 vertices belong to multiple faces and need special-case neighbor rules and canonicalization. Pentagons are genuine singularities. Substantial to implement correctly.

### (b) Explicit dual mesh + per-tile adjacency list  ← **RECOMMENDED / CHOSEN**
Generate the whole polyhedron once, assign each tile a stable integer `id`, and store:
```
%Tile{
  id: integer,
  center: {x, y, z},         # unit sphere
  corners: [ {x,y,z}, ... ], # ordered ring, 5 or 6
  neighbors: [id, ...],      # ordered ring, 5 or 6
  is_pentagon: boolean
}
```
- **Pros:** neighbor lookup is a direct list read (no seam math at query time); trivially serializable; pentagons are just tiles with 5 entries — zero special-casing in gameplay code. This is exactly hexasphere.js's model.
- **Cons:** adjacency stored explicitly (`30f²` edges — ~87k for f=54, negligible); generation is one-time.

### (c) Known DGGS / library schemes
ISEA3H/ISEA7H (DGGRID), H3, HEALPix/rHEALPix, DGGAL: production-grade, equal-area, hierarchical — but heavyweight, geospatial-focused, no native Elixir. Overkill for a game.

**Why "Civ-style is not a sphere":** Civilization-type maps are a **cylinder** — flat axial/offset hex grid wrapping east-west with hard top/bottom edges (polar ice hides the discontinuity). A true sphere cannot be tiled by hexagons alone (Euler) — you must introduce the 12 pentagons, which is precisely the Goldberg construction.

## 3. Exact geometry pipeline

### Step 1 — Icosahedron vertices (golden-ratio construction)
`φ = (1 + √5) / 2 ≈ 1.618034`. The standard 12 vertices (cyclic permutations of `(0, ±1, ±φ)`) are **edge-up**. For vertex-up, construct directly (unit radius):
- North pole: `(0, 0, 1)`; South pole: `(0, 0, −1)`
- Upper ring, 5 vertices at latitude `+atan(1/2)`: `z = 1/√5`, ring radius `ρ = 2/√5`, longitudes `θ_k = k·72°`, `k=0..4` → `(ρ·cos θ_k, ρ·sin θ_k, 1/√5)`
- Lower ring, 5 vertices at latitude `−atan(1/2)`: `z = −1/√5`, `ρ = 2/√5`, longitudes offset 36°: `θ_k = 36° + k·72°`

Check: `tan(lat) = (1/√5)/(2/√5) = 1/2` → `lat = atan(1/2) = 26.565°`. ✓

The 20 faces: 5 north-cap fans (pole + upper-ring pairs), 10 equatorial antiprism-band triangles, 5 south-cap fans.

### Step 2 — Subdivide each triangular face
For each face `A,B,C`, generate a triangular lattice of frequency `f`:
```
P(i,j) = ( (f−i−j)·A + i·B + j·C ) / f,   i,j ≥ 0, i+j ≤ f
```
`(f+1)(f+2)/2` points per face, `f²` small triangles per face (`20f²` total). **Deduplicate** points shared along the 30 edges and 12 vertices — hexasphere.js keys points by rounded coordinate string; better in Elixir: **topological keys** ({:v, vertex}, {:e, edge, t}, {:f, face, i, j}) which are exact. Optionally use geometric slerp instead of linear interpolation for more even spacing (linear-then-normalize is fine for gameplay).

### Step 3 — Project to sphere (normalize)
For each point `p`: `p̂ = p / ‖p‖`, then scale by world radius `R`.

### Step 4 — Dual / Voronoi → tiles
**Dual (deterministic — use this):** Every vertex of the subdivided icosahedron becomes **one tile center**. Its tile's **corners** are the centroids of the triangles incident to that vertex, projected to the sphere. Interior vertices touch 6 triangles → hexagon; the 12 original icosahedron vertices touch 5 → pentagon. Order the centroid ring by angle around the center.
(The Voronoi-from-scattered-points route — Fibonacci sphere + stereographic Delaunay — is for *irregular* tiles; not needed here.)

### Step 5 — Per-tile output
```
tile.center  = normalized vertex · R
tile.corners = [ centroid(t) · R for each incident triangle t ], ordered CCW around center
tile.neighbors = tiles sharing an edge (see §4)
```

## 4. Neighbor topology

- Every tile has **6 neighbors**, except the **12 pentagons** (original icosahedron vertices) which have **5**.
- **Deriving adjacency:** in the dual, two tiles are adjacent **iff their center-vertices share an edge in the subdivided triangular mesh**. So:
  1. Build the subdivided-icosahedron edge set (each small triangle contributes 3 vertex-pairs; dedupe).
  2. For tile `V`, neighbors = all vertices sharing an edge with `V`.
  3. Order them by angle of `(neighbor.center − V.center)` projected into `V`'s tangent plane, so `neighbors[i]` and `corners[i]` line up (edge shared with `neighbors[i]` lies between `corners[i]` and `corners[i+1]`).
- Total adjacency edges = `30f²`.
- **Pentagons as mountains:** a pentagon is just a tile with a 5-entry `neighbors` list; marking the 12 as `terrain: :mountains, traversable: false` requires no special topology handling.

## 5. Distance & pathfinding

Confirmed: **no global axial `(q,r)` coordinate exists on a sphere** (the 12 pentagons are the "defects" that make any global hex coordinate impossible). Standard approaches:

- **Grid/graph distance:** BFS over `neighbors` for uniform cost; A*/Dijkstra for weighted terrain.
- **A\* heuristic = great-circle distance** between tile centers:
  ```
  d = R · atan2( ‖a × b‖ , a · b )      # a, b = unit center vectors (numerically robust)
  # or  d = R · acos( clamp(a·b, −1, 1) )
  ```
  Admissible if scaled to ≤ the minimum per-step ground distance (divide by average edge length in tiles).
- **Approximate ring distance** in tiles: `great_circle_angle / average_angular_tile_spacing`.

## 6. Seamless terrain noise

Sample **3D noise at each tile's unit-sphere center `(x,y,z)`** — inherently seamless because the domain is the actual 2-sphere embedded in ℝ³; no wrap seam, no polar pinch (unlike 2D noise over lat/lon).

**3D fBm layering:**
```
elevation(p) = Σ_{i=0}^{octaves−1}  gain^i · noise3D( p · (frequency · lacunarity^i) )
```
- `p` = unit center (optionally offset by a seed vector so worlds differ).
- Typical: `octaves = 5–8`, `lacunarity = 2.0`, `gain = 0.5`; base `frequency` controls continent size.
- Simplex/OpenSimplex preferred over classic Perlin (fewer directional artifacts) but classic Perlin 3D works. Domain warping (`noise3D(p + warp·noise3D(p))`) adds richer coastlines.
- 4D noise only needed for *animated* seamless noise; static terrain needs only 3D.
- Generation is `O(tiles)` and embarrassingly parallel (`Task.async_stream`).

## 7. Where the 12 pentagons land (vertex-up)

| Pentagon group | Count | Latitude | Longitudes |
|---|---|---|---|
| North pole | 1 | **+90°** | (pole) |
| Upper ring | 5 | **+atan(1/2) = +26.565°** | 0°, 72°, 144°, 216°, 288° |
| Lower ring | 5 | **−atan(1/2) = −26.565°** | 36°, 108°, 180°, 252°, 324° |
| South pole | 1 | **−90°** | (pole) |

= 6 pentagons per hemisphere (pole + ring of 5), rings offset **36°** (pentagonal antiprism). Angular gap pole↔ring and ring↔ring = icosahedron edge angle `acos(1/√5) ≈ 63.435°`.

## 8. Open-source implementations worth cribbing

- **hexasphere.js — arscan / Rob Scanlon** (JS, no deps; powers the "Encom Globe"). icosahedron → subdivide edges into `subDivisions` segments → project → tiles from triangle centroids around each vertex. Exposes `tile.centerPoint {x,y,z}`, `tile.boundary` (ordered corner ring), `tile.neighbors`. Dedupes shared points via coordinate-string hash. Params: `radius`, `subDivisions` (= `f`), `tileWidth` (inward padding). **Best direct reference for an Elixir port.** github.com/arscan/hexasphere.js
- **OptimisticPeach/hexasphere** (Rust) — subdivision with slerp; efficient index math.
- **SergeySave/hexasphere** (Java) — same model.
- **Hallada, "Generating icosahedrons and hexspheres in Rust"** (hallada.net/2020/02/01) — clearest walkthrough: vertices → recursive subdivision → "truncation" mapping each vertex to incident-triangle centroids. Adjacency emerges from shared-edge topology.
- **redblobgames** — "Delaunay/Voronoi on a sphere" (redblobgames.com/x/1842) and "Procedural planet generation" (x/1843) — for irregular Voronoi variants.
- **Heavyweight DGGS**: DGGRID (ISEA3H/7H), H3, rHEALPix, DGGAL — reference for seam/pentagon handling rigor only.

## Suggested Elixir data model (concrete)

```elixir
%World{
  frequency: 54,            # f → 29_162 tiles
  radius: 1.0,
  tiles: %{id => %Tile{}}   # map for O(1) id lookup
}

%Tile{
  id:          non_neg_integer(),
  center:      {float, float, float},   # unit vector
  corners:     [{float,float,float}],   # ordered ring, len 5 or 6
  neighbors:   [id],                    # ordered ring, len 5 or 6
  pentagon?:   boolean()
}
```
Terrain/elevation stored separately as `%{tile_id => terrain}` derived from seed. Great-circle distance on `center` gives A\* heuristic and range queries.

## Sources
- https://en.wikipedia.org/wiki/Goldberg_polyhedron
- https://github.com/arscan/hexasphere.js/ · demo: https://www.robscanlon.com/hexasphere/
- https://github.com/optimisticpeach/hexasphere
- https://www.hallada.net/2020/02/01/generating-icosahedrons-and-hexspheres-in-rust.html
- https://www.redblobgames.com/x/1842-delaunay-voronoi-sphere/ · https://www.redblobgames.com/x/1843-planet-generation/
- https://mathworld.wolfram.com/RegularIcosahedron.html
- DGGRID manual v6.4, dggridR vignette, DGGAL (dggal.org)
