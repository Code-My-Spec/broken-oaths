# Persist the mutable delta over the seed, never derived world data

## Status
Accepted

## Context
A GP(54,0) world is 29,162 tiles of terrain, elevation, and geometry —
all a pure function of the world seed. Gameplay adds mutable state on
top: players, units, cities, regions, orders, fog-of-war exploration,
turn number. Storing derived data would bloat Postgres and create
consistency bugs between stored terrain and the generators.

## Options Considered
- **Store everything** (tiles as rows) — simple queries, but ~30k rows
  per world of redundant data that can drift from the generator version.
- **Delta-over-seed** — persist only what players change; recompute
  terrain/mesh from the seed on boot.

## Decision
Delta-over-seed. Postgres stores worlds (seed, frequency, turn, age),
users, units, cities, regions, orders, and per-player exploration masks
— never tiles, terrain, or geometry. `WorldServer` rehydrates in
`init/1` by regenerating the world from its seed and loading the delta;
writes back on a write-behind cadence (turn tick, last-viewer-leaves,
shutdown). Derived-data caches (mesh, facets, textures) live in
`:persistent_term` with versioned keys so hot reloads and generator
changes invalidate cleanly.

## Consequences
- Generator changes alter existing worlds' terrain: acceptable pre-launch;
  post-launch, generator versioning must be stored per world.
- Fog-of-war masks are per-player and potentially large (up to 29k
  tiles); representation (bitset vs tile-id set) is a component-spec
  decision, but it persists as part of the delta.
- Event sourcing is deferred; the pure core should still emit events so
  it remains an additive upgrade.
- Research basis: `.code_my_spec/knowledge/liveview_game_architecture.md`.
