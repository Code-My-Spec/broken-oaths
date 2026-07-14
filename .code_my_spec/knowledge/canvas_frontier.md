# Canvas 2D Performance Frontier (2024–2026)

Research brief for the Globe3D renderer. Written 2026-07-13.

## What we render today (baseline for every number below)

One main-thread 2D canvas inside a `phx-update="ignore"` wrapper (`lib/broken_oaths_web/live/world_live/show.ex`, the `.Globe3D` colocated hook). Two paths, chosen by LOD:

- **Far mode — `renderCanvas()`** (`show.ex:1335`): a per-pixel equirect warp. For every pixel inside the globe disc it does inverse-rotation, `atan2`/`asin` → texture lookup, day/night smoothstep, cloud blend, then one `putImageData` of the whole `Uint32Array` frame. Backing store is deliberately downscaled (`q = 0.4` coarse / `0.5` desktop, `show.ex:1149`) and CSS-upscaled — that's the "fuzzy at distance" look and the reason it's only ~200k px/frame instead of ~800k.
- **Near mode — `renderPolygons()`** (`show.ex:1239`): ~1500 (touch) / 7500 (desktop) budgeted tiles, painter-sorted, each doing `beginPath` + 5–7 `lineTo` + `fill` + same-color `stroke` + a **second** translucent cloud `fill`. So roughly **2 fills + 1 stroke per tile** — on desktop that's ~15–20k path ops/frame. dpr-sharp, capped at 2 (`show.ex:1155`).
- **Selection ring** (`drawSelection()`, `show.ex:1309`) stroked on top of either path.

Units, buildings, cloud-puffs and particles are slated to land as **additional per-frame draw layers on this same canvas** — that's the pressure this brief is about.

---

## 1. Per-op budgets (order-of-magnitude, desktop; halve-to-quarter for mobile)

There is no official per-op table; the honest numbers come from benchmark harnesses and vendor write-ups. Treat these as **shape of the cost curve**, not guarantees — they move 2–4x with sprite size, dpr, and GPU.

| Operation class | Cost signal | Practical frame budget (16.7 ms) |
|---|---|---|
| `drawImage` of a small pre-rendered sprite | AG Charts: 100k stamps in **66.9 ms** ≈ 1.5M/s | ~15–25k/frame desktop, ~3–6k mobile |
| Path fill (`beginPath`→`fill`), few points | AG Charts: 100k arcs **287 ms** naive → **15.4 ms** batched (18x) | naive ~1–3k complex fills/frame; **path fills are ~10–20x costlier than a sprite stamp** |
| `stroke` | comparable to a fill; a second pass over the same path | counts as another fill |
| `putImageData` (whole frame) | one bulk copy; cost ∝ pixel count, **not** GPU-composited | our ~200k px warp fits; scales linearly — don't `putImageData` a dpr-2 full-screen buffer per frame |
| `getImageData` | **read-back stalls the pipeline**; can force a GPU→CPU sync | never per-frame (we only do it once at texture decode, `show.ex:1065` — correct) |
| `fillText` / glyph | MDN: "avoid text rendering whenever possible" | pre-rasterize; see §4 |

Key structural fact from the WICG canvas thread: **2D has no way to batch draws except paths** — every primitive is one CPU-side API call, and "a few thousand elements" of naive copying can hit "a few seconds per frame," while pre-rendered sprites reach ~14k smoothly animated. Our per-tile double-fill+stroke is exactly the expensive quadrant; our future units should be the cheap (sprite) quadrant.

Sources: [AG Charts — Optimising HTML5 Canvas](https://blog.ag-grid.com/optimising-html5-canvas-rendering-best-practices-and-techniques/) · [MDN — Optimizing canvas](https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Optimizing_canvas) · [WICG — Why is canvas 2d so slow?](https://discourse.wicg.io/t/why-is-canvas-2d-so-slow/2232/) · [MeasureThat — putImageData vs drawImage vs fillRect](https://www.measurethat.net/Benchmarks/Show/17589/0/putimagedata-vs-drawimage-vs-fillrect)

---

## 2. Layering: stacked canvases + static caching (the single biggest structural win)

The core insight (MDN, IBM, AG Charts all agree): **a 2D canvas has no memory** — to move one unit you must clear and redraw the whole scene. If terrain and units share a canvas, every unit tween forces a full ~200k-px warp or ~20k-path re-render.

**When separate canvases win:** when a layer changes at a different rate than the layer above it. Our terrain changes only on camera settle and the 10s terminator creep (`show.ex:1042`); units/particles/selection change every frame. That's the textbook case for splitting.

Recommended stack (CSS-positioned, shared `phx-update="ignore"` wrapper, ascending z-index):

1. **Terrain** (warp far / polygons near) — redraw **only** on camera change or terminator tick. Otherwise it just sits there, composited for free by the browser.
2. **Weather/particles** — per-frame, cheap sprite stamps.
3. **Units/buildings** — per-frame, sprite stamps (or redraw only when a unit moves, via a dirty flag).
4. **Selection/UI** — trivially cheap, redraw per frame.

AG Charts' dirty-flag scene graph shows the payoff: "redraws only dirty groups while reusing unmodified layer bitmaps." For us the terrain layer becomes ~0 cost on idle-camera frames — which is *most* frames once units are the thing moving.

**Caveat for our hook:** each canvas is more backing-store memory (see §7) and more compositor layers. Cap at ~3–4 canvases, cap dpr at 2 (already done), and `releaseCanvas` them in `destroyed()`. Don't over-split — 10 layers is its own tax.

Sources: [IBM — Optimize HTML5 canvas rendering with layering](https://developer.ibm.com/tutorials/wa-canvashtml5layering/) · [MDN — Optimizing canvas](https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Optimizing_canvas) · [AG Charts](https://blog.ag-grid.com/optimising-html5-canvas-rendering-best-practices-and-techniques/)

---

## 3. OffscreenCanvas in a Worker for the per-pixel warp

The warp is pure CPU math over ~200k pixels — the ideal thing to move off the main thread so drags/LiveView stay responsive.

**Support (2026):** Chrome/Edge 69+, Firefox 105+, **Safari 16.4+** (macOS and iOS). The 2D context and `OffscreenCanvas` constructor are reliable inside a *dedicated* Worker; Shared/Service workers are not. iOS 16.4 shipped in early 2023, so real-world coverage is now broad but **not universal — keep the main-thread path as fallback**.

**The lifecycle trap that matters for us:** `transferControlToOffscreen()` is **one-way**. Once a `<canvas>` is transferred to a worker, calling `getContext` on it from the main thread throws `InvalidStateError`. Our near-mode polygons, `unproject()` hit-testing, and selection ring all need main-thread geometry on the *same* canvas — so a naive full transfer would strand them.

**Recommended pattern — don't transfer the visible canvas. Ship pixels back as an `ImageBitmap`:**
1. Worker owns a plain `new OffscreenCanvas(w,h)` (or just computes the `Uint32Array`), does the warp.
2. Worker calls `createImageBitmap(imageData)` and `postMessage(bmp, [bmp])` (ImageBitmap is transferable — zero-copy).
3. Main thread `ctx.drawImage(bmp, 0, 0)` onto the terrain layer.

This keeps the visible canvas on the main thread (so near mode, unproject, and selection are untouched), moves only the expensive far-mode math off-thread, and the `drawImage` of one bitmap is cheap. It also composes cleanly with §2's layering.

**Hook gotchas:**
- Colocated hooks are inline `<script>` — a Worker needs a URL. Use a `Blob`/`URL.createObjectURL` inline worker so we keep the **no-npm, no-separate-asset** constraint.
- Tear down in `destroyed()`: `worker.terminate()` + revoke the blob URL, or the worker leaks across LiveView navigations.
- The texture `Uint32Array` and cloud tex must be `postMessage`'d into the worker once (transfer or copy) after decode.
- Use `requestAnimationFrame` **inside** the worker (not the deprecated `commit()`), or drive it by posting camera state on each main-thread rAF.

Reality check: if you're already GPU-bound elsewhere this won't add FPS, but it *will* remove main-thread jank during drags — which is the actual felt problem. If the warp ever needs to be full-res/dpr-2, this stops being enough and §6 (a shader) is the answer.

Sources: [web.dev — OffscreenCanvas](https://web.dev/articles/offscreen-canvas) · [MDN — OffscreenCanvas](https://developer.mozilla.org/en-US/docs/Web/API/OffscreenCanvas) · [MDN — transferControlToOffscreen](https://developer.mozilla.org/en-US/docs/Web/API/HTMLCanvasElement/transferControlToOffscreen) · [gremlich.me — OffscreenCanvas 2025](https://www.gremlich.me/software-engineering/2025/offscreen-canvas/)

---

## 4. Sprites, atlases, ImageBitmap, and glyph markers

For units/buildings/cloud-puffs the rule is uniform: **pre-render once, `drawImage` many.**

- **Pre-render to an offscreen sprite** (MDN's first technique): draw each unit type once to a small offscreen canvas/`OffscreenCanvas`, then stamp with `drawImage`. This turns per-frame path work into O(1) draws — AG Charts' "offscreen sprite" path.
- **`createImageBitmap` + a single shared atlas** is the fast variant. A May-2026 discussion in ghostty-web found that a cache pattern **only beats direct rendering when it uses `ImageBitmap` and one shared texture**; an atlas held as a plain `OffscreenCanvas`/`HTMLCanvasElement` benched *slower* than drawing directly. So: build one `ImageBitmap` atlas, `drawImage(atlas, sx,sy,sw,sh, dx,dy,dw,dh)` sub-rects — don't keep a canvas-per-sprite.
- **Emoji/text glyphs as unit markers:** `fillText` per frame is in MDN's "avoid" list and re-shapes/re-rasterizes every call. **Rasterize each glyph once into the atlas at dpr scale, then stamp the bitmap.** This also fixes crispness at dpr 2–3 — bake the glyph at `size * dpr` and draw down, rather than letting the text renderer fight subpixel positions each frame.
- **Integer destination coords** for stamps: `drawImage` at fractional x/y triggers extra anti-aliasing (MDN). `Math.floor` sprite positions (our polygon fills legitimately stay subpixel for smooth rotation — this rule is for sprites only).
- **Path2D caching:** limited value *here*. Path2D pays off when the same geometry replays across frames; our polygon corners are recomputed every frame from the rotating camera, so there's nothing static to cache. Skip it for terrain; it could help a fixed-shape UI overlay.

Sources: [MDN — Optimizing canvas](https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Optimizing_canvas) · [ghostty-web #163 — per-frame fillRect alternatives](https://github.com/coder/ghostty-web/issues/163) · [MeasureThat — Canvas cache or Path2D](https://www.measurethat.net/Benchmarks/Show/13670/0/canvas-cache-or-path-2d) · [AG Charts](https://blog.ag-grid.com/optimising-html5-canvas-rendering-best-practices-and-techniques/)

---

## 5. Particles (rain / snow / battle FX): 500–2000 alongside current load

Fully feasible on a **dedicated particle layer** (§2) with pre-rendered sprites (§4):

- **Pool objects** — allocate a fixed particle array once, never `new` per spawn; GC pauses are the enemy of steady FPS.
- **One sprite (or a few) stamped N times.** 500–2000 `drawImage`s/frame is well inside the desktop budget (§1: ~15–25k/frame headroom) and fits mobile (~3–6k) *if* they're the only per-frame cost on that layer — which is exactly why the terrain must be on its own cached layer first.
- **Never path-draw particles** (`arc`+`fill` each) at these counts — that's the 287 ms/100k quadrant. A rain streak or snow dot is a 1–2 px sprite.
- Web-worker particle simulation is reported to lift frame rates 40–60% with 1000+ objects, but that's usually unnecessary if the *draw* is cheap; reach for it only if the physics (not the blitting) dominates.

Sources: [WICG — canvas 2d slow (14k particles via pre-render)](https://discourse.wicg.io/t/why-is-canvas-2d-so-slow/2232/) · [reintech — Optimizing Canvas for large-scale apps](https://reintech.io/blog/optimizing-canvas-performance-large-scale-apps) · [Arkounay/2D-Canvas-Image-Particles](https://github.com/Arkounay/2D-Canvas-Image-Particles)

---

## 6. The WebGL escape hatch, honestly

Two of our costs are textbook GPU wins, and one isn't worth migrating:

- **The far-mode warp is a fragment shader in disguise.** Equirect sample + day/night smoothstep + cloud blend is ~10 lines of GLSL running per-pixel on the GPU, at full res and dpr-2, essentially for free. This is the strongest case — and it can be done with **raw WebGL, no library**: one fullscreen quad, the baked equirect + cloud PNGs as textures, camera as uniforms. A few hundred lines, no npm, drops straight into the colocated hook.
- **Thousands of units** batch trivially in WebGL (one instanced draw vs. thousands of `drawImage`s). This is where **PixiJS** shines ("the fastest, most flexible 2D WebGL renderer," excels at sprite batching; v8 is a single import root, tree-shakeable, WebGPU-capable). But Pixi is a heavy dependency and violates the no-npm/no-build posture; a CDN UMD bundle is possible but large and CSP-awkward. `regl`/`twgl` are thin helpers (twgl even lower-level than regl) if you want batching without the framework.
- **Near-mode polygon terrain is NOT a compelling migration.** ~7500 flat-shaded hexes/frame is comfortably within 2D canvas, and it buys clean hit-testing and the LiveView-testable event path. Don't move it.

**Smallest sensible migration if 2D ever cracks:** hand-written WebGL for *only* the far-mode impostor (keeps no-npm), leave polygons + units + selection on 2D canvas layers. Full Pixi is a last resort reserved for "we have 10k+ animated units and batching is the wall." Cost/benefit: the shader warp is high-payoff/medium-effort and preserves constraints; a Pixi rewrite is high-effort and breaks the no-npm rule — only justified by a scale we don't have yet.

Sources: [PixiJS v8 launch](https://pixijs.com/blog/pixi-v8-launches) · [PixiJS home](https://pixijs.com/) · [areknawo — Your WebGL aiders (regl/twgl)](https://areknawo.com/your-webgl-aiders/) · [friendzy — WebGL vs HTML5 for browser games 2025](https://friendzy.xyz/2025/07/22/webgl-vs-html5-for-browser-games/)

---

## 7. Mobile cliffs (iOS Safari especially)

- **Total canvas memory ~384 MB per tab** on iOS 15+ (lower on older, device-dependent). Exceed it and Safari throws "Total canvas memory use exceeds the maximum limit" and blanks canvases.
- **Per-canvas pixel cap:** width×height ≤ **16,777,216** (e.g. 4096×4096). A max canvas = 4096×4096×4 = **64 MB**. Eight of them = 512 MB → over budget.
- **The dpr trap:** backing store bytes = `cssW·cssH·dpr²·4`. At dpr 3 a full-screen canvas is **9x** the CSS-pixel cost. Our §2 layering multiplies this by the layer count — 4 full-viewport layers at dpr 2 on a large phone can approach the budget. Mitigations we should keep/add: **cap dpr at 2** (already done, `show.ex:1155`), keep the far-mode backing store downscaled (already `q<1`), and `releaseCanvas` (set `w=h=1`) every layer in `destroyed()` so LiveView navigations don't accumulate 64-MB corpses.
- **`getImageData` stalls / `InvalidStateError`:** reading back is slow and can invalidate an over-size canvas on Safari. We only read once at decode (fine). Never add a per-frame read; prefer `putImageData`/`drawImage(bitmap)` for writes.
- **Coarse-pointer budget:** we already branch on `(pointer: coarse)` for tile budget and `q` — extend the same gate to particle counts and layer count.

Sources: [PQINA — Total canvas memory exceeds limit](https://pqina.nl/blog/total-canvas-memory-use-exceeds-the-maximum-limit/) · [PQINA — Canvas area exceeds maximum limit](https://pqina.nl/blog/canvas-area-exceeds-the-maximum-limit/) · [Apple Developer Forums — canvas memory](https://developer.apple.com/forums/thread/687866) · [pica #231 — getImageData InvalidStateError on Safari](https://github.com/nodeca/pica/issues/231)

---

## Apply to this project — ranked (effort × payoff)

1. **Split terrain onto its own cached canvas layer; redraw it only on camera-settle / terminator tick.** (Effort: medium · Payoff: very high.) This is the enabling move — it makes units/particles cheap because they stop forcing a terrain re-render. Do this *before* adding any moving layer. §2.
2. **Add units/buildings/particles as a separate per-frame sprite layer, drawn from one `ImageBitmap` atlas with pooled objects and integer coords.** (Effort: medium · Payoff: high.) Keeps the new content in the cheap sprite quadrant and off the terrain layer. §4, §5.
3. **Move the far-mode warp into an inline (Blob-URL) Worker, returning an `ImageBitmap` — do NOT `transferControlToOffscreen` the visible canvas.** (Effort: medium-high · Payoff: high on jank, neutral on raw FPS.) Removes drag/LiveView stutter; preserves near mode, unproject, and selection on the main thread. Keep a main-thread fallback for pre-16.4 Safari. §3.
4. **Pre-rasterize emoji/text unit markers into the atlas at dpr scale instead of per-frame `fillText`.** (Effort: low · Payoff: medium.) Fixes crispness at dpr 2–3 and removes text-shaping cost. §4.
5. **Memory hygiene: cap dpr at 2 (done), cap layer count ~3–4, `releaseCanvas` every layer in `destroyed()`, gate particle/layer counts on `(pointer: coarse)`.** (Effort: low · Payoff: medium — prevents hard iOS crashes, not FPS.) §7.
6. **Batch/state-hygiene pass on `renderPolygons`: set `fillStyle` runs together, reconsider the per-tile second cloud `fill`.** (Effort: low · Payoff: low-medium.) The double-fill+stroke per tile is our costliest near-mode item; a shared cloud overlay pass could halve path ops. §1.
7. **Keep raw-WebGL-shader-warp in the back pocket; do NOT migrate polygons or adopt Pixi yet.** (Effort: high · Payoff: high but premature.) Revisit the shader warp only if #3 isn't enough for full-res/dpr-2 far mode; revisit Pixi only at 10k+ animated units. §6.
