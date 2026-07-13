# Codebase Map: Hex World Feature (pre-globe baseline)

Repo: `/Users/johndavenport/Documents/github/broken_oaths` (Phoenix 1.8.3 / LiveView 1.1 / Elixir, DaisyUI + Tailwind v4 + esbuild).

Snapshot date: 2026-07-12, before the hex-globe conversion. This documents the flat cylindrical hex world that the globe replaces.

## 1. Files involved

### Backend — `lib/broken_oaths/worlds/`

**`world.ex` (21 lines)** — Ecto schema `BrokenOaths.Worlds.World`, table `"worlds"`.
- Fields: `name:string`, `seed:integer`, `width:integer default 200`, `height:integer default 150`, `status:string default "active"`, timestamps.
- `changeset/2`: casts all fields, requires `:name` + `:seed`, `unique_constraint(:seed)`.
- Terrain is NOT stored — only metadata (seed + dimensions). Terrain is generated on demand from the seed.

**`../worlds.ex` (48 lines)** — Context `BrokenOaths.Worlds` (CRUD).
- `list_worlds/0` (ordered by `inserted_at desc`), `get_world!/1`, `create_world/1`, `update_world/2`, `delete_world/1`, `change_world/2`.
- `random_world_name/1` (line 42): seeds `:rand` (`:exsss`, tuple derived from seed), picks one `@adjectives` + one `@nouns` word (20×20 pool) → deterministic name.

**`noise.ex` (79 lines)** — `BrokenOaths.Worlds.Noise`. 2D **Perlin** noise (classic Ken Perlin gradient noise, NOT simplex). `import Bitwise`. Full interface:
- `init(seed)` (line 12): seeds `:rand` (`:exsss`, tuple derived from seed), shuffles `0..255`, doubles the list → 512-element tuple permutation table for overflow-safe indexing.
- `noise2d(perm, x, y)` (line 21): standard Perlin — integer cell via `&&& 255`, fractional part, `fade` smoothstep, gradient hashing, bilinear `lerp`; normalizes `[-1,1] → [0,1]` clamped.
- `fbm(perm, x, y, octaves \\ 6, lacunarity \\ 2.0, persistence \\ 0.5)` (line 53): Fractal Brownian Motion — sums octaves with `frequency = lacunarity^i`, amplitude decaying by persistence, normalized by `max_val`.
- Private: `fade/1` (6t⁵−15t⁴+10t³), `lerp/3`, `grad2d/4` (4-direction gradient via `hash &&& 3`).
- Interface note for globe work: this is a **planar 2D** noise sampler. It has no spherical/3D variant. A globe needs 3D noise sampled on the sphere surface to avoid seam artifacts.

**`generator.ex` (118 lines)** — `BrokenOaths.Worlds.Generator`. Terrain classification.
- Constants: `@elevation_scale 0.035`, `@moisture_scale 0.045`.
- `@terrain_types` (lines 11-20): elevation-threshold list → `{0.30 ocean, 0.35 shallow_water, 0.40 beach, 0.60 grassland, 0.75 plains, 0.85 forest, 0.92 hills, 1.01 mountains}`.
- `generate_terrain_map(seed, width, height)` (line 26): two independent perm tables (`seed` for elevation, `seed + 12345` for moisture); nested comprehension over all `q×r` → `%{{q, r} => terrain_atom}` (a 200×150 = 30,000-entry map for defaults). Each cell = `fbm(elevation, 6 octaves)` + `fbm(moisture, 4 octaves)` → `classify_terrain`.
- `generate_hex_terrain(seed, q, r)` (line 41): single-hex version.
- `terrain_stats(terrain_map)` (line 50): reduces to `[{terrain, count, pct}]` sorted desc.
- `find_spawn_points(terrain_map, count, world_width)` (line 64) + `select_spread_points`/`do_select`: picks grassland hexes spread apart using wrap-aware `dq = min(dq, w - dq)` distance. (Not currently wired into the LiveView — utility function.)
- `classify_terrain/2` (line 99): `base_terrain` by elevation, then `modify_by_moisture` (grassland↔forest/plains, plains→grassland).

**`hex_math.ex` (61 lines)** — `BrokenOaths.Worlds.HexMath`. Flat-top hex axial math (cites redblobgames). `@sqrt3`.
- `axial_to_pixel(q, r, hex_size)` (line 15): `x = size*1.5*q`, `y = size*(√3/2*q + √3*r)`.
- `neighbors(q, r, world_width, world_height)` (line 22): 6 axial directions `[{1,0},{1,-1},{0,-1},{-1,0},{-1,1},{0,1}]`, each passed through `wrap_coordinates`, `nil` rejected.
- `distance(q1,r1,q2,r2)` (line 29): cube-distance.
- `wrap_coordinates(q, r, w, h)` (line 40): **east-west wraps** `rem(rem(q,w)+w,w)`; **north-south hard boundary** returns `nil` when `r<0` or `r>=h`. This is the topology definition.
- `hex_width/1`, `hex_height/1`, `horizontal_spacing/1`, `vertical_spacing/1` helpers.
- Note: `HexMath` is fully unit-tested but the LiveView `Show` re-implements its pixel/neighbor math inline rather than calling it (see §2).

### Frontend — `lib/broken_oaths_web/live/world_live/`

**`index.ex` (74 lines)** — `WorldLive.Index`. Lists worlds as DaisyUI cards. Events: `new_world` (random seed+name, create, `push_navigate`), `delete_world`. Inline `render/1` HEEx.

**`show.ex` (411 lines)** — `WorldLive.Show`. The main renderer/interaction surface. This is where the rendering pipeline lives (details in §2). Module constants: `@zoom_levels [3,5,8,12,18,25]`, `@default_zoom_index 2`, `@pan_step 10`, `@container_w 960`, `@container_h 700`, `@terrain_legend` (8 `{atom, hexcolor, label}`). Events: `select_hex`, `regenerate`, `update_name`, `zoom_in`, `zoom_out`, `pan`, `keydown` (WASD/arrows/±), `switch_world`. Inline `render/1`.

### Assets

- **`assets/css/app.css` (135 lines)** — Tailwind v4 entry + DaisyUI themes + the hex CSS (§2).
- **`assets/js/app.js` (83 lines)** — standard Phoenix bootstrap. **No custom hooks.**
- **`assets/vendor/`** — `topbar.js`, `daisyui.js`, `daisyui-theme.js`, `heroicons.js` (vendored, imported by relative path). No Three.js / WebGL.
- **`assets/tsconfig.json`** — editor autocompletion only; comments confirm "basic esbuild setup without node_modules". There is **no `package.json` and no `node_modules`** in `assets/`.

## 2. Rendering pipeline (terrain_map → visible_hexes → HTML)

The pipeline is **100% server-side rendered HTML divs with CSS `clip-path`** — no SVG, no canvas, no WebGL.

1. **`mount/2`** (`show.ex:28`): loads world, calls `Generator.generate_terrain_map(seed,width,height)` → stores full `terrain_map` (all 30k hexes) in socket assigns, plus `viewport: %{x:0,y:0}`, `zoom_index`, `hex_size`, then `compute_view/1`.

2. **`compute_view/1`** (`show.ex:180`) — the culling/layout core. Given `terrain_map`, `viewport`, `hex_size`, `world`:
   - `hex_w = round(hs*2)`, `hex_h = round(hs*√3)`.
   - Visible window: `cols = min(div(960, hs*1.5)+2, width)`, `rows = min(div(700, hs*√3)+2, height-vp.y)` — computes only the hexes that fit the 960×700 viewport (viewport culling).
   - Builds `visible_hexes` (`show.ex:191`): for each `dq,dr`, wraps `q = rem(vp.x+dq, width)` (east-west wrap), `r = vp.y+dr` (clamped to height). Pixel position **inline** `px = hs*1.5*dq`, `py = hs*(√3/2*dq + √3*dr)` (same formula as `HexMath.axial_to_pixel`, but duplicated here, not called). Each hex = `%{q, r, x, y, terrain}`, terrain via `Map.get(tm, {q,r}, :ocean)`.
   - Assigns `visible_hexes`, `hex_w`, `hex_h`, `grid_w`, `grid_h`.

3. **`render/1`** (`show.ex:240`) — the grid (`show.ex:285-303`):
```heex
<div class="hex-grid-viewport" style={"position:relative;width:#{@grid_w}px;height:#{@grid_h}px;"}>
  <div :for={hex <- @visible_hexes}
    class={["hex-cell", terrain_class(hex.terrain), @selected_hex == {hex.q, hex.r} && "hex-selected"]}
    phx-click="select_hex" phx-value-q={hex.q} phx-value-r={hex.r}
    style={"left:#{hex.x}px;top:#{hex.y}px;width:#{@hex_w}px;height:#{@hex_h}px;"}
    title={"(#{hex.q}, #{hex.r}) #{hex.terrain}"}>
  </div>
</div>
```
Each hex = one absolutely-positioned `<div>`. `terrain_class/1` (`show.ex:218`) → `"hex-#{terrain}"` maps to a CSS background color.

4. **The hex shape — CSS `clip-path` polygon** (`assets/css/app.css:107-134`):
```css
.hex-cell {
  position: absolute;
  clip-path: polygon(75% 0%, 100% 50%, 75% 100%, 25% 100%, 0% 50%, 25% 0%);
  cursor: pointer;
  transition: filter 0.1s ease;
}
.hex-cell:hover { filter: brightness(1.3); z-index: 1; }
.hex-selected  { filter: brightness(1.5) drop-shadow(0 0 4px rgba(255,255,255,0.8)); z-index: 2; }
.hex-ocean { background-color: #1e3a8a; }
.hex-shallow_water { background-color: #3b82f6; }
.hex-beach { background-color: #fbbf24; }
.hex-grassland { background-color: #22c55e; }
.hex-plains { background-color: #84cc16; }
.hex-forest { background-color: #15803d; }
.hex-hills { background-color: #92400e; }
.hex-mountains { background-color: #525252; }
```
The `polygon(75% 0%, 100% 50%, 75% 100%, 25% 100%, 0% 50%, 25% 0%)` clips a rectangular div into a flat-top hexagon.

Interaction is all server round-trips: clicking a hex fires `phx-click="select_hex"` → `handle_event("select_hex", ...)` (`show.ex:59`) → updates `selected_hex`/`selected_terrain` → re-render. Zoom/pan likewise re-run `compute_view` server-side.

## 3. Coordinate system & topology

- **Axial coordinates** `(q, r)`, **flat-top** hexagons (redblobgames convention).
- **Topology: CYLINDRICAL, not toroidal.** Confirmed in two places:
  - `HexMath.wrap_coordinates/4` (`hex_math.ex:40`): `q` wraps modulo width (east-west seam joins), `r` returns `nil` outside `[0, height)` (north/south are hard edges/poles). Docstring `hex_math.ex:36-37`: *"East-west: wraps around. North-south: hard boundaries."*
  - `Show.compute_view` (`show.ex:198`) wraps `q` but clamps `r`; `Show.do_pan` (`show.ex:169`) wraps x `rem(rem(vp.x+dx,w)+w,w)` and clamps y `max(0, min(vp.y+dy, h-1))`.
- Neighbor directions: `[{1,0},{1,-1},{0,-1},{-1,0},{-1,1},{0,1}]` in `HexMath.neighbors`.
- **Globe implication:** the current model is a cylinder (wrap E-W, hard N-S poles). A true hex globe cannot be a regular axial grid — a sphere tiled with hexes requires 12 pentagons (Goldberg polyhedron / geodesic), so the axial `(q,r)` + modulo-wrap scheme does not extend directly to a sphere.

## 4. Noise / terrain (see §1 for full interface)

- `noise.ex` is classic **2D Perlin** + FBM, seeded & deterministic, planar.
- `generator.ex` classifies via two independent noise fields: elevation (6-octave FBM, scale 0.035) → base terrain by `@terrain_types` thresholds; moisture (4-octave FBM, scale 0.045) → biome modifier. Elevation and moisture use different seeds (`seed` and `seed+12345`).

## 5. JS hooks — VERIFICATION

**There are no LiveView JS hooks** — no drag-to-pan, no scroll-zoom hooks exist (a prior memory claiming otherwise was wrong).
- `app.js` (`assets/js/app.js:25,32`): imports `{hooks as colocatedHooks} from "phoenix-colocated/broken_oaths"` and registers `hooks: {...colocatedHooks}` — but the generated colocated module `_build/dev/phoenix-colocated/broken_oaths/index.js` contains exactly `export const hooks = {};` (empty).
- `grep` for `phx-hook` / colocated hook definitions across `lib/` returns nothing. No `.js` files under `lib/` or `assets/js/` beyond `app.js`.
- Pan is implemented via server-side buttons (`phx-click="pan" phx-value-dir=...`, `show.ex:308-322`) and keyboard (`phx-window-keydown="keydown"` on the root div `show.ex:242`, handled at `show.ex:137`). Zoom is server-side buttons/keys (`show.ex:263-265`, `handle_event` `show.ex:111/122`). No client-side drag or wheel handling anywhere.

## 6. Tests (`test/`) — all worlds-related

- **`test/broken_oaths/worlds_test.exs` (124 lines)** — context CRUD: `list_worlds`, `get_world!`, `create_world` (defaults, custom dims, required name/seed, unique seed), `update_world`, `delete_world`, `random_world_name` (2-word, deterministic, distinct).
- **`test/broken_oaths/worlds/noise_test.exs` (140 lines)** — `init/1` (512-tuple, 0..255, deterministic, mirrored halves), `noise2d/3` (range [0,1], deterministic, varies, continuity, negative/zero/large coords), `fbm/3` (range, deterministic, octave detail, map-scale variety).
- **`test/broken_oaths/worlds/hex_math_test.exs` (154 lines)** — `axial_to_pixel` (origin, x/y deltas, scaling), `neighbors` (6 interior, exact coords, **E-W wrap both directions, N/S clip**), `distance` (self=0, adjacent=1, symmetric, per-axis), `wrap_coordinates` (passthrough, wrap ≥width & negative, nil out-of-range r, boundary), hex dimensions.
- **`test/broken_oaths/worlds/generator_test.exs` (156 lines)** — `generate_terrain_map` (complete map, bounds, valid atoms, deterministic, seed-varies, variety, full-size ok), `generate_hex_terrain` (matches map), `terrain_stats` (per-type, ~100% sum, counts, sort order), `find_spawn_points` (count, grassland-only, fewer-if-scarce, spread).
- **`test/broken_oaths_web/live/world_live/show_test.exs` (113 lines)** — renders hex grid, legend, stats; select hex; regenerate changes seed; zoom in/out; pan changes viewport; keyboard nav; name update; world switcher navigation.
- **`test/broken_oaths_web/live/world_live/index_test.exs` (42 lines)** — empty state, list, create+redirect, delete.
- **`test/support/fixtures/worlds_fixtures.ex` (24 lines)** — `world_fixture/1` helper.

## 7. Build / asset pipeline

- **Bundler: esbuild** (`config/config.exs:48-54`): `js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.`; `NODE_PATH` points at `deps` + build path (so JS deps like `phoenix`, `phoenix_live_view` resolve from Elixir deps, not npm).
- **CSS: Tailwind v4** (`config.exs:58-64`): `--input=assets/css/app.css --output=priv/static/assets/css/app.css`. CSS entry is `assets/css/app.css` (`@import "tailwindcss"`, DaisyUI plugins/themes, hex styles). Sources scanned: `../css`, `../js`, `../../lib/broken_oaths_web`.
- **mix aliases** (`mix.exs:79-90`): `assets.setup` = tailwind/esbuild install; `assets.build` = `compile` + `tailwind broken_oaths` + `esbuild broken_oaths`; `assets.deploy` = minified builds + digest. `compilers: [:phoenix_live_view] ++ Mix.compilers()` (`mix.exs:13`) — enables colocated-hook extraction.
- **Deps** (`mix.exs:41-56`): phoenix 1.8.3, phoenix_live_view 1.1, esbuild 0.10 (v0.25.4), tailwind 0.3 (v4.1.12), heroicons (github). **No Three.js, no WebGL, no npm/package.json.**
- **Vendored deps** live in `assets/vendor/` and are imported by relative path (per `app.js` comments).

## 8. Routes (`lib/broken_oaths_web/router.ex`)

Inside `live_session :worlds, layout: {BrokenOathsWeb.Layouts, :app_full}` (`router.ex:25`):
- `live "/worlds", WorldLive.Index, :index` (`router.ex:26`)
- `live "/worlds/:id", WorldLive.Show, :show` (`router.ex:27`)

(The `:worlds` live_session is separate from the authenticated user live_sessions further down; worlds are not auth-gated in this block.)

## Key findings for the globe conversion

1. **Rendering is server-rendered HTML divs clipped by CSS `clip-path` polygon** (`app.css:111`) — no canvas/SVG/WebGL layer at all.
2. **No JS hooks exist.** All pan/zoom is server-side via `phx-click`/`phx-window-keydown`.
3. **Topology is a CYLINDER** (`hex_math.ex:40`, `show.ex:169/198`). The axial `(q,r)` grid with modulo wrapping does not map to a sphere — a hex-tiled globe is a Goldberg polyhedron requiring 12 pentagons.
4. **Noise is planar 2D Perlin** (`noise.ex`) sampled on `(q,r)`. On a globe: sample 3D noise on the sphere surface. The generator cleanly separates elevation/moisture and is deterministic from seed, so it can be reused re-parameterized by 3D position.
5. **Terrain is not persisted** — only `{seed, width, height}` stored (`world.ex`), regenerated on every mount (`show.ex:32`).
6. **`HexMath` is well-tested but bypassed** — `Show.compute_view` reimplements pixel math inline (`show.ex:198-199`).
