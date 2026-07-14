# CSS-3D Frontier — Hybrid Set Pieces Over a Canvas Globe

Research date: 2026-07-13. Sources are 2024–2026 unless a foundational reference is unavoidable. Cited inline and collected at the end.

## Scope & framing

The production board is **canvas-rendered** (texture impostor far, vector polygons near — see `board_architecture.md`). This document does **not** re-litigate rendering thousands of facets in DOM (settled in `hexglobe_css3d_feasibility.md`: infeasible past a few thousand). It researches the DOM/CSS-3D frontier for two surviving roles:

1. **`?renderer=css3d`** — the preserved windowed `matrix3d` facet renderer (orthographic, no perspective). Maintenance-mode; §7 covers engine changes that threaten it.
2. **HYBRID SET PIECES** — the live question. Tens (not thousands) of rich DOM elements floating over the canvas world: city detail pop-outs, animated capital markers, unit cards, victory banners. At this element count the entire performance calculus inverts — the constraints that killed full-DOM globes (layer explosion, per-frame quad count) are irrelevant, and DOM's strengths (accessibility, text layout, transitions, hit-testing, filters/blend lighting) become free.

**The single most important finding:** for set pieces, the right architecture is **not** CSS-3D-with-`preserve-3d` at all. It is **2D-projected billboards** — DOM elements positioned every frame from the canvas camera's own projection of a world-space anchor, exactly the Three.js "align HTML to 3D" pattern ([threejs.org, align-html-elements-to-3d]). We already own the projection math server-side and in the canvas hook; reusing it to drive `element.style.transform` on tens of divs is trivially cheap and pixel-accurate. `preserve-3d` is reserved for *internal* richness of an individual set piece (a card that tilts, a marker that spins), never for placing set pieces in the world.

---

## 1. Billboarded DOM sprites over a 3D scene

### The canonical technique (project-per-frame, not preserve-3d)

The Three.js manual's "Aligning HTML Elements to 3D" is the reference implementation and maps 1:1 onto our canvas hook ([threejs.org]). Per frame, for each anchor's world position `P`:

```js
// 1. world position -> normalized device coords (-1..+1) via the SAME camera the canvas uses
tempV.copy(P); tempV.project(camera);
// 2. NDC -> CSS pixels
const x = ( tempV.x * 0.5 + 0.5) * canvas.clientWidth;
const y = (-tempV.y * 0.5 + 0.5) * canvas.clientHeight;
// 3. position the DOM billboard (centered on the point)
elem.style.transform = `translate(-50%,-50%) translate(${x}px,${y}px)`;
```

Our advantage: we do not need Three.js. We already compute the orthographic (or windowed) projection of unit-sphere points on the server and in the canvas renderer. A set-piece's anchor is just another unit-sphere point run through the *same* `Projection` used for tile centers, so the billboard lands exactly on the tile it belongs to — no drift between the canvas world and the DOM overlay.

### Counter-rotation

For **pure billboards** there is nothing to counter-rotate — a DOM element is inherently screen-facing; you only translate it. Counter-rotation is only needed if a sprite is parented into a `preserve-3d` scene that itself rotates (then you apply the inverse yaw/pitch to keep the face flat). Because our set pieces are screen-space translated, we sidestep counter-rotation entirely. This is the decisive simplification over trying to embed set pieces *inside* the css3d facet scene.

### Cost, jitter, `will-change` budget at tens of elements

- **Cost:** writing `style.transform` on ~10–50 elements per frame is negligible. The Three.js manual's own warning is that **raycasting for occlusion** is the slow part — and we don't need it (§6, dot-product cull is analytic). Keep the overlay inside the existing single `phx-update="ignore"` wrapper so LiveView never patches hook-mutated transforms (the attribute-war trap from `board_architecture.md`).
- **Jitter/blur avoidance:** fractional translate values cause subpixel blur and shimmer. Round to the device pixel grid: `Math.round(v * dpr) / dpr` ([drei #2380] documents the blurry-text-from-subpixel-translate3d failure and this fix). The classic `0.01deg` micro-rotation hack forces sub-pixel AA on Firefox ([bugzilla 739176]) but prefer explicit dpr rounding — it matches how the canvas already snaps.
- **`will-change` budget:** promote **only** billboards that are actively animating, and drop the hint the moment the animation ends ([web.dev/speed-layers]; [browser-rendering GPU limits]). Target < ~5 active compositor layers during motion; a 4096² RGBA layer costs 64 MB, and two or three exhaust a mobile GPU budget. At tens of set pieces this is easy to honor — but a blanket `will-change: transform` on every set piece is the same layer-explosion footgun called out for facets. Gate it per-element on animation state.

---

## 2. Best modern CSS-3D demos and what they teach

| Author / demo | Element count | What it teaches for set pieces |
|---|---|---|
| **Amit Sheen** — "3D in CSS, and the True Meaning of Perspective"; Frontend Masters "Pushing CSS to the Limit"; CSS-Tricks "3D Layered Text: Motion & Variations" (2024–25) | tens | Depth via **layered pseudo-elements**, lighting as **chiaroscuro gradients/`filter`** rather than real lights, and "**Computational CSS**"/typed arithmetic to drive many layers from a few custom props. This is exactly the vocabulary for a rich unit card or animated capital marker. ([css-tricks.com/author/amitsheen], [smashingconf workshop]) |
| **Julia Miocene** — "Sunday CSS #10: 3D in CSS is not real"; Pure CSS 3D characters (2024–25) | tens–low hundreds | The core caution: CSS "3D" has **no depth buffer** — everything is manual matrix + z-index ordering, and heavy scenes "may not work well on all computers." Reinforces keeping set-piece internals shallow. ([codepen.io/miocene], [alvaromontoro June 2025]) |
| **Ana Tudor** — CSS polyhedra (collection nMbprD) | tens of faces | Per-face `matrix3d` from a tangent basis — same math the `css3d` facet renderer uses. Proof of correctness, not of scale. |
| **Niels Leenheer** — "CSS is DOOMed" (2026) | ~couple thousand | The ceiling reference (already in the feasibility doc): one camera transform over thousands of pre-rasterized divs hits 60fps on desktop but **crashes iOS Safari** when pushed. Confirms set pieces must stay in the tens. |

**Lesson synthesis:** modern CSS-3D excellence is about *richness per element at low counts* — gradient lighting, layered depth, custom-property-driven motion — not element count. That is precisely the set-piece niche.

---

## 3. `@property` (registered custom properties) driving many transforms

- **Why it's needed:** an unregistered custom property is an untyped string and **cannot be interpolated**; a registered one with `syntax:'<angle>'` (or `<number>`/`<percentage>`) can animate/transition smoothly ([css-tricks.com/exploring-property]; [MDN registering-properties]).

```css
@property --yaw { syntax: '<angle>'; inherits: false; initial-value: 0deg; }
```

- **One property → many child transforms:** yes. A single registered `--yaw` (or `--x`/`--y`) can feed any number of children via `calc()`/`var()` in their `transform` — the CSS-Tricks car example drives translate **and** rotate from shared props. So a whole set-piece cluster can be posed by animating one variable.
- **Invalidation cost at N elements — the caveat neither article quantifies:** if N elements' `transform` reference a shared `--yaw`, changing `--yaw` invalidates and recomputes style/transform for **all N** each tick. `inherits:false` matters here — it narrows recalc scope so children aren't reparsed on unrelated changes ([MDN]). This is the same class of cost as the `board_architecture.md` warning where one state-class toggle over thousands of 3D elements cost 31s of recalc. **At tens of elements it's a non-issue; do not scale a shared-`--yaw` scheme to hundreds.**
- **Practical placement:** use `@property`-driven transforms for the *internal* animation of a single set piece (a marker's idle spin, a banner's reveal). Use the JS project-per-frame path (§1) for *world placement*, because placement depends on the live canvas camera, which CSS can't read.

---

## 4. View Transitions API + scroll-driven animations for game UI

### View Transitions (2025 state)

Same-document VT reached **Baseline Newly Available in Oct 2025** (Firefox 144 joined Chrome/Edge 111+, Safari 18+) ([developer.chrome.com/blog/view-transitions-in-2025]). Relevant 2025 additions:

- **Scoped transitions** — `element.startViewTransition()` on a subtree (Chrome 140+): run a transition on just the set-piece layer without freezing the whole page. This is the right primitive for a **zoom-to-city pop-out** appearing/morphing.
- **Nested view-transition groups** (Chrome 140+): restores **clipping and 3D transforms** *during* the transition — previously impossible with a flat pseudo tree. Directly useful if a set piece uses `preserve-3d` internally and must keep its depth while animating in.
- **`match-element` auto-naming** (Chrome 137+) for lists of markers/cards without hand-assigning names.
- **`ViewTransition.waitUntil()` / `waitUntil` async gating** (late 2025) to hold a transition until data (city detail) loads.

**Hard limitation:** VT snapshots **DOM**, not canvas frames. It can animate a DOM set piece appearing over the canvas, but it **cannot** tween the canvas world itself (a camera dolly on the globe stays the canvas hook's job). So VT is a UI-chrome tool (pop-outs, banners, card→fullscreen), not a camera tool.

### Scroll-driven animations (`scroll()`/`view()`)

Run on the **compositor thread**, no JS scroll listeners ([smashingmagazine 2024]; [MDN scroll-driven]). Support: Chrome/Edge 115+ (2023), **Safari 26 (Sept 2025)** with threaded support in 26.4, **Firefox still behind `layout.css.scroll-driven-animations.enabled` as of 152 (June 2026)** — ~82% global, not Baseline, polyfill exists ([caniuse]). **Fit for this game is weak:** the globe camera is pointer/drag-driven, not scroll-driven; there's no long scroll surface to bind a timeline to. Possible niche only: a scrollable side panel (tech tree, unit roster) with view()-progress reveals — orthogonal to the canvas. Do not build camera moves on scroll timelines.

---

## 5. Perspective mode: a perspective overlay above an orthographic canvas globe

The `css3d` renderer we keep is deliberately **orthographic** (no `perspective` → no foreshortening), matching the canvas globe's projection. Two questions for set pieces:

- **Does mixed projection look wrong?** Only if a set piece spans a large fraction of the screen. CSS `perspective` is "distance to the z=0 plane"; small values = strong foreshortening ([css-tricks.com/how-css-perspective-works]; Amit Sheen, "True Meaning of Perspective"). A globe rendered orthographically next to a strongly-perspective element reads as inconsistent **at large scale**. But a **small** set piece (a unit card a few hundred px wide) can carry its *own local* `perspective` for internal tilt/parallax without visibly clashing with the ortho globe — the eye accepts local perspective on a small UI object floating in screen space.
- **`perspective-origin` matching:** if you ever want a set piece to feel anchored *into* the world rather than floating on the glass, set its `perspective-origin` toward the canvas camera's principal point (screen center for a centered ortho camera) so its vanishing direction agrees with where the globe's "camera" sits. For pure screen-space chrome, leave origin centered.

**Recommendation:** keep world placement orthographic (§1) and reserve `perspective` for *inside* a set piece only, scaled small. Do not add global perspective to the overlay layer.

---

## 6. Depth integration — set pieces respecting the globe's horizon

Two mechanisms, and at **tens** of elements the cheap one suffices:

1. **z-index by projected depth (sufficient default):** set `elem.style.zIndex = (-ndcZ * 0.5 + 0.5) * 100000 | 0` so nearer set pieces stack over farther ones and over the canvas ([threejs.org align-html]). Wrap the overlay in its own stacking context (`position:absolute; z-index:0`).
2. **Analytic back-face cull for "behind the planet":** an anchor is on the far hemisphere when `dot(anchorNormal, viewDir) < threshold`. Hide it (`display:none`) or fade it near the limb. We compute this exactly (no raycaster needed) because the globe is a known unit sphere — the same visibility test the classic board uses for near-side tiles. This handles full occlusion for free.
3. **Limb clipping (only for elements straddling the horizon):** an element crossing the silhouette should be cut by the planet's circular edge. Apply a `clip-path: circle(R at cx cy)` matching the globe's projected disc, or a `mask`, on the overlay container. Modern `shape()` / `path()` clip functions allow a responsive circular limb ([web.dev clipping-masking]; [MDN clip-path]). This is per-frame-updatable but only worth doing for the few elements actually on the limb.

**Verdict:** ship z-index + dot-product cull. Add limb `clip-path` only if a specific set piece (e.g. a tall capital banner near the edge) visibly floats past the planet's edge.

---

## 7. Hard limits recap for the preserved `css3d` renderer (2025–2026 engine notes)

- **Blink layer squashing:** elements with a 3D transform are a "direct compositing reason"; Blink squashes overlapping non-3D layers into shared backing to avoid explosion ([chromium GPU-accelerated-compositing]). Our windowed facet cap (~1–2k) stays within the Ekioh-measured **200–600 MB** temporary-layer regime — do not let the window grow.
- **Safari preserved-layer fix:** Safari Technology Preview 243 (2025) fixed the Layers 3D view to **re-snapshot preserved layers after repaint** instead of showing stale textures, and to map textures to composited bounds — a real prior source of `preserve-3d` glitches on WebKit ([webkit.org STP 243]). Good news for the css3d renderer on Safari; re-QA `backface-visibility` + flattening there (the csswg #918 quirk from the feasibility doc still stands).
- **Flattening traps unchanged:** `clip-path`, `overflow != visible`, `filter`, `opacity < 1`, and `mix-blend-mode` still force `transform-style: flat` on the element they touch ([css-tricks.com/things-watch-working-css-3d]). Harmless on leaf facets/set pieces; **never** on the rotating `preserve-3d` container.
- **Emerging alternative — HTML-in-canvas (WICG):** `layoutsubtree` + `drawElementImage()` + `paint` event let real, accessible, laid-out DOM be drawn into a canvas/WebGL scene and return a transform for DOM sync; WebGL `texElementImage2D` / WebGPU `copyElementImageToTexture` can texture HTML onto 3D geometry ([github.com/WICG/html-in-canvas]). **Status: Chromium behind `chrome://flags/#canvas-draw-element`, Canary only, not standardized; CSS transforms on source elements are ignored for drawing.** Not usable in production yet, but it is the long-term convergence of the DOM-set-piece and canvas worlds — worth tracking. If it matures, city pop-outs could be authored as ordinary accessible DOM and composited *into* the canvas with correct depth, retiring the billboard-sync layer.

---

## Ranked next experiments

1. **Billboard overlay prototype (highest value, lowest risk).** Add a DOM overlay inside the existing `phx-update="ignore"` wrapper; drive N (~20) markers via project-per-frame from the canvas camera, dpr-rounded transforms, z-index-by-depth, analytic dot-product cull. Success = markers stay pinned to their tiles through drag/zoom with zero jitter. Reuses existing projection; no new math.
2. **Rich single set piece (unit card / capital marker) with `@property` internals.** One `matrix3d`/`preserve-3d` element, layered pseudo-elements + gradient chiaroscuro (Amit Sheen vocabulary), idle animation from one registered `--spin`/`--yaw`. Success = looks premium, holds 60fps, drops `will-change` when idle. Validates the "richness per element" thesis.
3. **Scoped View Transition for a city pop-out.** `element.startViewTransition()` on the set-piece layer for open/close and card→fullscreen, using nested groups to preserve any internal 3D. Success = smooth morph over the live canvas with no page-wide freeze. Gate on Chrome; graceful no-transition fallback elsewhere.
4. **Limb clipping pass.** Add `clip-path: circle()` (projected globe disc) to the overlay for elements flagged as straddling the horizon; measure whether it's visibly better than dot-cull alone. Likely only needed for tall edge banners.
5. **Perspective-matched anchored set piece (experimental).** Give one small set piece local `perspective` + camera-matched `perspective-origin` to test whether it reads as "sunk into" the world vs. floating. Decide keep/kill based on whether ortho-vs-perspective clash is visible at set-piece scale.
6. **Track HTML-in-canvas (watch, don't build).** Re-evaluate when `drawElementImage` ships unflagged in a stable Chromium and a second engine signals intent — potential future replacement for the entire billboard-sync layer.

## Sources
- Three.js — Align HTML Elements to 3D: https://threejs.org/manual/en/align-html-elements-to-3d.html
- HTML-in-Canvas (WICG explainer + `drawElementImage`/`layoutsubtree`, Canary flag): https://github.com/WICG/html-in-canvas · demo https://chrome.dev/html-in-canvas/demos/billboard.html
- View Transitions in 2025 (scoped, nested groups, match-element, waitUntil, Baseline Oct 2025): https://developer.chrome.com/blog/view-transitions-in-2025 · https://developer.mozilla.org/en-US/docs/Web/API/View_Transition_API
- Scroll-driven animations (timelines, support): https://www.smashingmagazine.com/2024/12/introduction-css-scroll-driven-animations/ · https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Scroll-driven_animations · https://caniuse.com/mdn-css_properties_animation-timeline_scroll
- `@property` animating powers / registration: https://css-tricks.com/exploring-property-and-its-animating-powers/ · https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Properties_and_values_API/Registering_properties
- Amit Sheen — "True Meaning of Perspective" (video) https://www.youtube.com/watch?v=LzDf8BizhmQ · CSS-Tricks author https://css-tricks.com/author/amitsheen/ · workshop https://smashingconf.com/online-workshops/workshops/complex-css-amit-sheen/
- Julia Miocene — CodePen https://codepen.io/miocene · "3D in CSS is not real" https://codepen.io/miocene/pen/rNoyLyO · roundup https://alvaromontoro.com/10-cool-codepen-demos/2025/06/
- Perspective mechanics: https://css-tricks.com/how-css-perspective-works/ · https://developer.mozilla.org/en-US/docs/Web/CSS/perspective
- CSS 3D flattening traps: https://css-tricks.com/things-watch-working-css-3d/
- Clipping/masking: https://web.dev/learn/css/paths-shapes-clipping-masking · https://developer.mozilla.org/en-US/docs/Web/CSS/clip-path
- Compositing / will-change / layer budget: https://web.dev/articles/speed-layers · https://www.browser-rendering.com/compositing-and-gpu-acceleration/hardware-acceleration-limits/gpu-memory-limits-in-chrome-compositing/ · https://www.chromium.org/developers/design-documents/gpu-accelerated-compositing-in-chrome/
- Subpixel jitter fixes: https://github.com/pmndrs/drei/issues/2380 · https://bugzilla.mozilla.org/show_bug.cgi?id=739176
- Safari preserve-3d snapshot fix: https://webkit.org/blog/17953/release-notes-for-safari-technology-preview-243/
- Prior internal docs: `hexglobe_css3d_feasibility.md`, `board_architecture.md`
</content>
</invoke>
