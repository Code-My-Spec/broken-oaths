# Custom Goldberg polyhedron mesh for the hex globe

## Status
Accepted (implemented)

## Context
The game board is a seamless hex globe, not a flat wrapping map. A sphere
cannot be tiled by hexagons alone — a Goldberg polyhedron GP(f,0) gives
10f²+2 tiles with exactly 12 pentagons. We need deterministic tile ids,
neighbor topology, and geometry, generated server-side in Elixir from a
world seed.

## Options Considered
- **Existing hexasphere libraries** — the mature ones (hexasphere.js,
  H3) are JavaScript/C or geo-indexing oriented; none provide an Elixir
  mesh with stable topological ids suitable for server-authoritative
  game state.
- **Project-local implementation** — build the icosahedron subdivision,
  topological dedupe, and dual mesh ourselves (~one module).

## Decision
No library — project-local code. `BrokenOaths.Worlds.Globe` builds
GP(f,0) (default f=54, 29,162 tiles) with vertex-up orientation,
topological dedupe keys for deterministic integer tile ids, per-tile
neighbor lists (5 or 6), and unit-sphere geometry. The 12 pentagons land
at the poles and ±26.57° rings and are forced to impassable mountains.
Companion modules: `Worlds.Projection` (orthographic camera math),
`Worlds.Noise` (3D Perlin/fBm sampled at tile centers — inherently
seamless on the sphere), `Worlds.Generator` (terrain classification).

## Consequences
- There is no global (q,r) coordinate system on a sphere: all gameplay
  (movement, vision, pathfinding) must be graph traversal over per-tile
  `neighbors` lists. Distance heuristics use `Projection.arc/2`.
- Mesh building is deterministic and cached in `:persistent_term` with
  versioned keys; a boot warm-up task pre-builds the default frequency.
- Research basis lives in `.code_my_spec/knowledge/hexasphere_geometry.md`
  and `worldgen_frontier.md` (graph algorithms for rivers/climate run
  unchanged on this mesh).
