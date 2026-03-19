# Hex World Generator - Implementation Status

## What's Done

### Worlds Bounded Context (`lib/broken_oaths/worlds/`)

Everything lives under the `Worlds` context - self-contained, no dependencies on the auth system.

| File | What it does | Status |
|------|-------------|--------|
| `worlds.ex` | Context module. CRUD for worlds, random name generator. | Done |
| `worlds/world.ex` | Ecto schema. Fields: name, seed, width, height, status. | Done |
| `worlds/noise.ex` | 2D Perlin noise with FBM (fractal Brownian motion). Seeded permutation table → deterministic output. | Done, needs tests |
| `worlds/hex_math.ex` | Flat-top hex grid math. Axial coords, pixel conversion, neighbors, distance, cylindrical wrapping. | Done, needs tests |
| `worlds/generator.ex` | Terrain generation. Dual Perlin layers (elevation + moisture) → 8 terrain types. Spawn point finder. | Done, needs tests |

### Database

| File | Status |
|------|--------|
| `priv/repo/migrations/20260319230000_create_worlds.exs` | Done. Creates `worlds` table with unique index on seed. |

Run: `mix ecto.migrate`

### LiveView Interface (`lib/broken_oaths_web/live/world_live/`)

| File | Route | What it does |
|------|-------|-------------|
| `index.ex` | `GET /worlds` | Lists saved worlds, "New World" button creates one with random seed+name and redirects to show. |
| `show.ex` | `GET /worlds/:id` | Main hex grid viewer. Viewport-based rendering, pan/zoom, hex selection, terrain stats sidebar. |

### Supporting Changes

| File | Change |
|------|--------|
| `assets/css/app.css` | Added `.hex-cell` with clip-path polygon, 8 terrain color classes, hover/selection effects. |
| `lib/broken_oaths_web/router.ex` | Added `/worlds` and `/worlds/:id` routes in a `:worlds` live_session with `app_full` layout. |
| `lib/broken_oaths_web/components/layouts.ex` | Added `app_full/1` layout (full-width, no padding) with "Worlds" nav link. |

## What's NOT Done

### Tests - NONE exist yet

Priority test files to create:

1. **`test/broken_oaths/worlds/noise_test.exs`** - Determinism (same seed = same output), output range [0,1], FBM produces values across the range
2. **`test/broken_oaths/worlds/hex_math_test.exs`** - Axial-to-pixel math, neighbor calculation, distance, wrapping at boundaries, cylindrical wrap
3. **`test/broken_oaths/worlds/generator_test.exs`** - Deterministic terrain maps, terrain classification thresholds, moisture modifier logic, terrain stats, spawn points
4. **`test/broken_oaths/worlds_test.exs`** - Context CRUD: create/get/update/delete world, unique seed constraint, random name generation
5. **`test/broken_oaths_web/live/world_live/index_test.exs`** - Page renders, create world redirects, delete world removes from list
6. **`test/broken_oaths_web/live/world_live/show_test.exs`** - Page renders with hex grid, select hex shows details, regenerate changes seed, pan/zoom update viewport, keyboard events

### Features not implemented

- Zoom controls could use scroll wheel (needs JS hook)
- No minimap overview
- No JSON export
- No spawn point visualization on the map
- Viewport doesn't use click-drag panning (only buttons/keyboard)
- East-west noise wrapping at the seam (terrain at q=0 and q=199 won't match - cosmetic only, coordinate wrapping works fine)

### Possible issues (couldn't compile to verify)

- The `~p"/worlds/#{id}"` verified route syntax - should work with Phoenix 1.8 but wasn't compile-tested
- The `app_full` layout referenced in the router's `live_session` - may need to be a template file instead of a function component depending on how Phoenix 1.8 handles live_session layouts
- HEEx template syntax in `show.ex` - the `:for` and `:if` attributes, `{expression}` interpolation should all work in Phoenix 1.8 but edge cases may exist
- `phx-window-keydown="keydown"` on the outer div for keyboard pan/zoom - should work but might need `phx-target={@myself}` or similar

## Architecture Notes

### Terrain Generation Flow

```
seed → Noise.init(seed) → permutation_table
     → Noise.init(seed + 12345) → moisture_table

For each hex (q, r):
  elevation = FBM(elevation_perm, q * 0.035, r * 0.035, 6 octaves)
  moisture  = FBM(moisture_perm, q * 0.045, r * 0.045, 4 octaves)
  terrain   = classify(elevation) |> modify_by_moisture(moisture)
```

Elevation thresholds:
```
0.00-0.30 → ocean       0.60-0.75 → plains
0.30-0.35 → shallow     0.75-0.85 → forest
0.35-0.40 → beach       0.85-0.92 → hills
0.40-0.60 → grassland   0.92-1.00 → mountains
```

Moisture modifiers: wet grassland → forest, dry grassland → plains.

### Hex Rendering

Viewport-based: only renders ~3000 hexes at a time (not all 30k). Container is ~960×700px. Each hex is absolutely positioned with inline `left`/`top` styles, sized by zoom level.

Flat-top hex clip-path: `polygon(75% 0%, 100% 50%, 75% 100%, 25% 100%, 0% 50%, 25% 0%)`

Pan moves the viewport origin (wraps east-west via modular arithmetic). Zoom changes hex circumradius from preset levels: [3, 5, 8, 12, 18, 25]px.

### Coordinate System

Axial coordinates (q, r) for flat-top hexagons per https://www.redblobgames.com/grids/hexagons/

- Pixel position: `x = size * 1.5 * q`, `y = size * (√3/2 * q + √3 * r)`
- Neighbors: `[(1,0), (1,-1), (0,-1), (-1,0), (-1,1), (0,1)]`
- Distance: `(|Δq| + |Δr| + |Δs|) / 2` where `s = -q - r`
- East-west wrap: `q_wrapped = rem(rem(q, width) + width, width)`
- North-south: hard boundary, `r` clamped to `0..height-1`

## Test Fixtures Needed

```elixir
# test/support/fixtures/worlds_fixtures.ex
defmodule BrokenOaths.WorldsFixtures do
  alias BrokenOaths.Worlds

  def world_fixture(attrs \\ %{}) do
    {:ok, world} =
      attrs
      |> Enum.into(%{
        name: "Test World #{System.unique_integer()}",
        seed: :rand.uniform(999_999_999),
        width: 200,
        height: 150
      })
      |> Worlds.create_world()

    world
  end
end
```
