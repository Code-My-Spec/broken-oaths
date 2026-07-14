# CSS-3D Deep Findings (specialist agents, 2026-07-13)

Collected from the five-angle CSS-3D research fan-out. Two reports below (animation/custom-properties, elevation/depth-sorting); lighting, perspective/limits, and scale/hybrid to be appended as they deliver. Every claim carried confidence + source in the originals; this file preserves the load-bearing conclusions.

**Meta-conclusion for this project:** both reports independently validate the canvas pivot. The canvas renderer dodges (a) the custom-property main-thread trap and (b) the Blink painter-path depth-sort landmine entirely. CSS-3D remains viable for the `?renderer=css3d` experiment and for *tens* of hybrid DOM set pieces — never thousands.

---

## Report 1 — Animation & custom-property transforms (angle3)

### The headline trap
A registered `@property --yaw` driving tile transforms is **NOT compositor-accelerated** — custom properties (registered or not) animate on the **main thread** (web.dev "Benchmarking CSS @property"; Bram.us 2023 "gotcha with animating custom properties"). The compositor cannot resolve `var()` substitution. HIGH confidence, multiple primary sources.

- Inherited property on `:root` → one JS write but **full-subtree style recalc** (~6k tiles) per frame.
- `inherits: false` → >800% cheaper recalc (web.dev benchmark) but requires per-element writes = 6k writes/frame, worse than our single parent-matrix write.
- Squeeze play: there is no configuration where var()-driven transforms beat the current single-rAF `matrix3d` parent write, which IS composited.

### The compositor-friendly JS-free alternative (if ever wanted)
WAAPI/keyframe animation of the parent `transform`/`rotate:` (individual transform properties are compositor-animated cross-browser since ~Aug 2024). **Trap:** matrix/rotate3d keyframes interpolate via quaternion slerp taking the SHORTEST path (CSSWG spec) — 0°→360° interpolates as "no rotation"; continuous spin needs chained sub-180° segments. `animation-timeline` (scroll-driven) is composited for 2D transforms; UNVERIFIED whether matrix3d stays composited under it.

### Billboarding (units/labels facing camera)
Counter-rotation via shared custom property works (CSS DOOM uses it) — one JS write, but main-thread recalc across all billboards, not composited. Under **orthographic** projection a single shared counter-rotation value is geometrically correct for all children. No public benchmark exists for hundreds of counter-rotating elements — must measure ourselves.

### Animated content on tiles (bobbing units)
Per-sprite CSS transform animations are compositor-eligible (each promoted to its own layer) — **dozens fine, hundreds risky**: layer count is the real cost (GPU texture memory; historic mobile crashes; ~50MB/layer illustrative figures). Never blanket `will-change`. Safari has a history of preserve-3d child-animation bugs — test there specifically.

### View Transitions API
Snapshot-based state transitions only; useless as a per-frame driver. Possible for discrete camera jumps / screen changes. Also (from Report 2): **Safari View Transitions flatten preserve-3d to a 2D snapshot mid-transition**.

### Recommendations (as delivered)
1. Keep parent rotation as the single rAF matrix3d write (already composited; hard to beat).
2. Bobbing units: plain CSS transform animations, strict layer budget.
3. Billboards: shared counter-rotation is correct under ortho; benchmark before scaling.
4. Validate ourselves: inherited-var recalc cost at 6k tiles; matrix3d under animation-timeline; Safari preserve-3d child animation.

---

## Report 2 — Elevation & depth-sorting (angle1)

### The headline risk
Extruding tiles (real translateZ relief) makes the surface **non-convex**, and Chrome has TWO sorting paths:

1. **Compositor (cc) path**: real BSP tree, splits intersecting polygons, CORRECT — but only for separately-composited quads. 6k tiles as individual compositing layers = memory death ("texture disappearance with numerous 3D-transformed surfaces").
2. **Blink paint path** (what 6k static-transform divs in one preserve-3d container actually use): **painter's algorithm by a single depth scalar — no Newell, no splitting**. This is the misordering-prone path, and it's the one our css3d architecture lands on. Misordering does NOT require true intersection — classic cyclic-overlap failures (prism sidewall vs neighbor's cap at grazing angles) suffice. (Chromium bug 99564; Ekioh devblog; CSS Transforms L2 spec mandates Newell's but engines diverge.)

Safari (Core Animation) genuinely attempts Newell's and handles intersections better; WebKitGTK TextureMapper BSP-splits and in 2024 added intersect-detection to skip splitting when unneeded (signal: splitting is expensive). Firefox has documented non-convex Z-order breaks (2016 data; current behavior unverified).

### Prior-art ceilings
- Codrops generative CSS voxel worlds (2025): ~32×32×12 stated ceiling; clip-path faces forced full repaint per frame (fix: sprite sheets).
- CSS DOOM (2026): "couple thousand" divs, 2.5D-friendly geometry, coplanar flicker fixed by epsilon offsets.
- No documented demo does non-convex heightfield at ~6k elements smoothly. Our target regime exceeds every published ceiling.

### Element-budget math for true extrusion
Extruded hex prism = cap + up to 6 walls. With backface culling + walls only at height discontinuities (Codrops constraint: neighbor heights differ ≤1 step): realistic ~1.5–3× element count, not 7×.

### Universal gotchas
- Near-coplanar facets z-fight in ALL engines; fix = deliberate epsilon translateZ offsets.
- `opacity<1`, `filter`, `overflow≠visible`, `clip-path≠none`, `mix-blend-mode` on any ancestor force flattening and destroy the 3D context.

### Recommendations (as delivered)
Prototype a few hundred extruded prisms at grazing angles in Chrome/Safari/Firefox before committing; options if Chrome paint path pops through: (a) keep extrusion subtle enough for scalar order to hold, (b) per-tile compositing for cliffs only, (c) **fake elevation with shading instead of translateZ so the surface stays convex** — note: (c) is exactly what the production canvas renderer does (radial lift is drawn, not composited), which sidesteps this entire class of problem.
