# Game Art Pipeline

Status: accepted (2026-07-14)

## Context

The game board is a canvas-2D orthographic projection of a hex globe —
no WebGL, no DOM tiles. Today every visual is programmer art: terrain
tiles are flat color-filled polygons (`Worlds.Terrain.color/1`), units
are colored circles, weather is translucent hex overlays. We now have
three art capabilities and need a doctrine for how art is produced and
how it lands on the board:

- **Aseprite** (compiled from source, driven by the pixel-plugin /
  pixel-mcp Claude Code plugin) — deterministic, scriptable pixel art.
- **Nano Banana** (`scripts/art-gen`, Gemini image API) — high-quality
  large-format generation. Hosted, paid-per-call, commercially usable.
- **Kenney Hexagon Pack** (`assets/art/kenney_hexagon_pack/`, CC0) —
  vendored reference/placeholder library.

Canvas 2D cannot perspective-map textures onto projected hex polygons
without triangle-subdivision hacks; tiles distort with curvature and
zoom. 29k tiles exist at frequency 54; a few hundred to a few thousand
render at once.

## Decision 1 — Billboards over texture mapping

In-game art is **billboard sprites drawn upright at projected tile
centers**, layered above flat color-filled terrain polygons. We never
texture-map tile surfaces on the canvas board.

- The color fill stays the terrain's ground truth (and matches the 3D
  world-preview texture baked from the same palette).
- Decor sprites (mountain peaks, hill bumps, tree clusters) sit on
  tiles whose relief/feature warrants them; unit/city sprites sit above
  decor. Draw order: terrain fill → fog wash → decor → weather → units.
- Sprites scale linearly with camera zoom (`k · scale · tile_arc`) and
  are skipped below a readability threshold instead of shrinking into
  noise. `imageSmoothingEnabled = false` so pixel art scales crisp.

## Decision 2 — Source by asset class

| Asset class | Source | Rationale |
|---|---|---|
| Units, terrain decor, buildings, UI icons (≤64px) | Pixel art via Aseprite + pixel-plugin | Deterministic, versionable, readable at tiny sizes, agent-drivable in the dev loop |
| Hero/marketing art, logo, world-picker cards, backgrounds | `scripts/art-gen` (Nano Banana; `--pro` for finals) | Quality tier; these render large in DOM contexts where diffusion output shines |
| Placeholders / style reference | Kenney pack (CC0) | Instant, zero-cost, license-clean |

3D asset generation (image-to-3D → Blender bake) is **rejected for
unit-scale art** — at ≤64px the downscale destroys everything 3D buys.
Revisit only for a one-time cohesive building-set bake.

## Decision 3 — Sprite conventions

- Base grid **32×32** (units, decor), transparent background, PNG.
- Live under `priv/static/images/game/{units,decor,buildings}/<name>.png`
  — committed to git like code. Aseprite source files (`.aseprite`)
  live in `assets/art/aseprite/` so sprites are editable later.
- Palette: anchored to the terrain palette in `Worlds.Terrain`
  (`@base_colors`/`@feature_colors`) plus the unit identity colors
  already on the board (lord `#f5c542`, settler `#42a5f5`) — new art
  must read against those grounds. Outline dark (`#1a1a1a`) for
  small-scale separation, matching the current unit ring.
- The client learns a tile's decor from the `game:window` push (a decor
  key derived server-side from relief/feature), never by re-deriving
  terrain client-side — fog filtering stays the single gate.

## Decision 4 — Board doctrine unchanged

Canvas paint is still never asserted in specs. Art changes the painter
only; the testable truth surfaces (`game:window`, `game:units`, …)
gain data (decor key) but lose nothing. Sprites failing to load must
degrade to the current programmer art (colored circles, plain fills) —
the board must never depend on an asset request to be playable.

## Consequences

- Unit/decor art can ship incrementally — any tile or unit without a
  sprite falls back to today's rendering.
- The 3D world preview (`WorldLive.Show`) keeps its baked-palette
  texture; art lands on the game board (`GameLive.Play`) first.
- Weather/fog remain translucent procedural overlays; they read as
  atmosphere against pixel sprites without style clash.
