# Hex Globe in Pure HTML/CSS — Feasibility Research (CSS 3D transforms & SVG)

Research date: 2026-07-12. **Outcome:** informed the chosen architecture — with the user's decisions (stepped rotation, visible-only rendering), we use **server-side orthographic projection per step** (no `preserve-3d` needed at all). This doc records the CSS-3D findings for reference, including the matrix3d technique if client-smooth rotation is ever added.

## TL;DR verdict

| Tiles (total) | ~Visible (front hemisphere) | CSS-3D divs (`clip-path` + `matrix3d`) | SVG orthographic re-projection |
|---|---|---|---|
| **2,500** | ~1,250 | Marginal on 2024 desktop; risky mobile | Marginal→smooth if batched/throttled |
| **10,000** | ~5,000 | Infeasible at 60fps without culling | Infeasible per-frame; OK on drag-end only |
| **30,000** | ~15,000 | Infeasible | Infeasible |

**Key finding:** both HTML-native approaches hit the same wall at a few thousand simultaneously-rendered facets, and the fix for both is identical — **never render the full tile set; cap on-screen facets** via near-side culling + DOM swapping/LOD. (With stepped server rendering, "per-frame" costs disappear entirely; only per-step re-render size matters — same regime as the old flat map's pan.)

Best real-world benchmark: Niels Leenheer's **"CSS is DOOMed"** (March 2026) — DOOM rendered as a static scene of "a couple thousand div elements" moved by one camera transform.

## 1. Prior art and element counts

- **Ana Tudor's "My CSS Polyhedra"** (CodePen collection nMbprD) — arbitrary flat-facet polyhedra via per-face `matrix3d`. Proof of correctness, tens of faces only.
- **Paul Hayes / Mamboleoo CSS spheres** — ring-and-panel spheres, ~200 elements; authors warn jank when pushing counts up.
- **David DeSandro intro-to-css-3d-transforms / CSS-Tricks "Think in Cubes"** — foundational technique (perspective, preserve-3d, one-transform-on-parent).
- **CSS DOOM (Niels Leenheer, 2026)** — closest analog: "a couple thousand div elements," one camera container transformed per frame; "browser only recalculates one element's styles per frame... composites hundreds of transformed divs in hardware at up to 60fps." But: "large maps can overwhelm the browser — Safari on iOS will crash if it becomes too much."

**Bottom line:** smooth in the low hundreds; couple-thousand is where stutter and mobile crashes appear; nobody runs 10k+ animated facets.

## 2. Performance limits & compositing

- Parent-only animation avoids re-rasterizing children (they rasterize once; per frame the compositor recomposites with the new parent matrix). **Cost is compositing thousands of quads + GPU memory for their textures, not repaint.**
- Cliffs: browser compositors are built for layered UI, not thousands of 3D surfaces. Ekioh measured Chrome allocating **~200–600 MB of temporary layer textures** for complex 3D CSS scenes (their Flow renderer: ~7 MB). Layer explosion → memory pressure, tile eviction.
- Realistic 60fps budgets (2024+ desktop, parent-only animation): ~500–1,000 facets comfortable; ~1,500–3,000 marginal; ≥5,000 infeasible without culling. Mobile ~1 order of magnitude worse (iOS Safari crashes at a couple thousand 3D-transformed elements).

## 3. Correctness gotchas

- **A. `clip-path` forces `transform-style: flat`** on the element it's applied to (also `overflow != visible`, `filter`, `opacity < 1` in Chrome/FF, `mix-blend-mode`). **Harmless on leaf tiles** (they don't need to establish a 3D context) — but never put these on the rotating `preserve-3d` container.
- **B. `preserve-3d` only affects immediate children** — avoid intermediate wrappers, or set preserve-3d on each.
- **C. Safari quirks** with `backface-visibility` + flattening; Safari doesn't force flattening on `opacity < 1`. Test culling in Safari (csswg-drafts #918).
- **D. Depth sorting:** browsers sort preserve-3d siblings by z and run Newell's algorithm; splitting only needed for intersecting planes (Chrome sorts those arbitrarily; only Safari splits correctly). A **convex** Goldberg polyhedron has non-intersecting facets → sorting is correct. Residual: hairline seams from subpixel rounding.
- **E. Pointer events** follow the clipped shape and account for transforms in Chrome; Firefox has non-standard clip-path pointer behavior; WebKit bug #152548 (clip-path clipping pointer events). QA clicks per browser.
- **F. `perspective` + `overflow`:** mask on an outer wrapper, never on the preserve-3d element.

## 4. The math — facet tangent to sphere (matrix3d)

Transform chain: outer `.viewport { perspective: P }`; `.globe { transform-style: preserve-3d; transform: rotateX(β) rotateY(α); will-change: transform }` (the ONLY per-frame change); each leaf tile gets a precomputed `matrix3d` + `backface-visibility: hidden` + per-tile `clip-path`.

For tile center direction **N** (unit, outward normal), tangent basis **T**, **B** = N × T, center **C** = N·R. CSS `matrix3d` is column-major `[T | B | N | C]`:

```js
function tileMatrix3d(n, R, up = [0, 1, 0]) {
  const dot = n[0]*up[0] + n[1]*up[1] + n[2]*up[2];
  const ref = Math.abs(dot) > 0.99 ? [1, 0, 0] : up;   // degenerate-basis guard at poles
  let t = normalize(cross(ref, n));
  const b = cross(n, t);
  const C = [n[0]*R, n[1]*R, n[2]*R];
  return `matrix3d(${t[0]},${t[1]},${t[2]},0, ${b[0]},${b[1]},${b[2]},0, ${n[0]},${n[1]},${n[2]},0, ${C[0]},${C[1]},${C[2]},1)`;
}
```

- **Per-tile `clip-path` percentage polygons DO encode each Goldberg tile's true shape:** project the tile's real corners into its tangent basis (dot with T, B), normalize to bounding box, emit `polygon(x% y%, ...)`. Pentagons and slightly-irregular hexagons each get their own polygon.
- Chord-plane vs tangent-plane facet: use the true flat polygon (chord plane) for perfect edge matching; visually indistinguishable.
- **Seams:** subpixel rounding → hairline gaps. Standard fix: ~1–2% overlap (`scale(1.015)` or inflate the clip-path) or 1px same-color border. Overlap beats gaps.

## 5. Mitigations for high tile counts (ordered by impact)

1. **Near-side-only rendering + DOM swap** — only mount tiles with `dot(N, viewDir) > threshold`; swap DOM as rotation crosses thresholds; hard budget ~1,000–2,000 rendered tiles. LiveView-friendly (server holds the graph).
2. **LOD** — coarser super-facets far away, or flat low-poly globe during drag, full detail on drag-end.
3. **Flat single-color tiles** — no repaint during rotation (doesn't lift the quad-count ceiling much though).
4. **`content-visibility: auto`** off-screen; `contain: layout paint` per tile.
5. **`will-change: transform` ONLY on `.globe`** — on thousands of tiles it's the classic layer-explosion footgun.
6. JS culling loop every few frames (CSS DOOM does exactly this to survive).

## 6. SVG orthographic re-projection alternative

d3-geo `geoOrthographic()` or hand-rolled; recompute visible tiles' polygon points on drag. Correct occlusion free (you compute visibility), no layer explosion; but d3 community consensus: use canvas for rotating globes — thousands of separate SVG elements animating per frame is too slow (~30k point updates/frame at 5k hexes). SVG's niche: drag-time LOD fallback, or weak-GPU devices.

**CSS-3D divs beat SVG at 10k** (recomposite < recompute-points-per-frame; keeps clip-path styling + native hit-testing; convex solid neutralizes SVG's occlusion advantage).

## 7. Final ratings (desktop 60fps)

| Tiles | CSS-3D raw | CSS-3D + culling to ~1–2k | SVG per-frame | SVG drag-end only |
|---|---|---|---|---|
| 2,500 | Marginal | **Smooth** | Marginal | Smooth |
| 10,000 | Infeasible | **Smooth–marginal** | Infeasible | Marginal |
| 30,000 | Infeasible | Marginal (needs LOD) | Infeasible | Marginal |

Mobile: budget a few hundred–1,000 rendered facets max.

## How this fed the final decision

The user chose **stepped rotation** (matching the existing pan UX) and noted the flat view already renders only visible hexes. That removes the per-frame constraint entirely: the server re-projects the visible cap once per step and LiveView diffs the divs — the same cost profile as the existing `compute_view/1` pan. No preserve-3d, no matrix3d, no backface-visibility needed; just orthographic math in Elixir + per-tile inline `clip-path`. The CSS-3D matrix3d technique above remains the upgrade path if smooth client-side drag is ever wanted (render budget ~1–2k tiles + parent-transform rotation).

## Sources
- https://nielsleenheer.com/articles/2026/css-is-doomed-rendering-doom-in-3d-with-css/ · https://github.com/NielsLeenheer/cssDOOM
- https://www.ekioh.com/devblog/3d-environments-in-css/ (Newell's algorithm, 200–600MB layer cost)
- https://css-tricks.com/things-watch-working-css-3d/ (clip-path/overflow/filter flattening)
- https://codepen.io/collection/nMbprD (Ana Tudor polyhedra)
- https://paulrhayes.com/creating-a-sphere-with-3d-css/ · https://www.mamboleoo.be/articles/create-your-own-sphere-in-css
- https://franklinta.com/2014/09/08/computing-css-matrix3d-transforms/
- https://github.com/w3c/csswg-drafts/issues/918 · https://bugzilla.mozilla.org/show_bug.cgi?id=689498 · https://bugs.webkit.org/show_bug.cgi?id=152548
- https://web.dev/articles/speed-layers · https://web.dev/articles/content-visibility
- https://d3js.org/d3-geo · https://observablehq.com/@michael-keith/draggable-globe-in-d3
