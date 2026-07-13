# Hex Globe Rendering in the Browser — WebGL/Three.js Baseline (NOT chosen)

Research date: 2026-07-12. **Decision: this approach was NOT chosen** — the user prefers pure HTML/CSS with stepped rotation (see `hexglobe_css3d_feasibility.md` and the implementation plan). Kept as reference in case client-side smooth rotation is ever wanted later.

## 0. Local context (verified)

- Phoenix 1.8.3, phoenix_live_view 1.1.0, esbuild 0.25.4, tailwind 4.1.12.
- **No `package.json` anywhere** — the Phoenix "no-npm" asset pipeline. Vendor JS lives in `assets/vendor/` imported via relative paths; esbuild bundles `js/app.js` with `--alias:@=.` and `NODE_PATH` at `deps/`.
- `app.js` wires phoenix-colocated hooks (`import {hooks} from "phoenix-colocated/broken_oaths"`), but no hooks are defined.

## 1. Rendering approach comparison

| Approach | Per-tile color | Picking | Hover | Rotate/zoom | 60fps @ 10k tiles | Verdict |
|---|---|---|---|---|---|---|
| **(a) Three.js, single BufferGeometry, vertex colors** | Trivial | Raycast → faceIndex → tileId | Recolor tile verts | OrbitControls | Yes, easily (1 draw call) | Best WebGL option |
| (b) Raw WebGL | Manual everything | Manual | Manual | Manual | Yes | Reimplements 80% of three.js for no gain |
| (c) SVG / CSS 2D per-frame re-projection | Easy | DOM click free | CSS :hover free | Re-project + rewrite DOM per frame | **No** | Fails at scale for *smooth* rotation |

Why WebGL for smooth rotation: rotating a globe smoothly means re-projecting every visible tile every frame; DOM/SVG cannot do thousands of per-frame mutations at 60fps. A single WebGL mesh uploads geometry once; rotation is a camera matrix change. (Note: with **stepped** rotation — the chosen UX — this whole argument dissolves, which is why we went CSS.)

## 2. Three.js specifics

### 2.1 One BufferGeometry (never per-tile meshes)
10k meshes = 10k draw calls = frame death. Merge into one non-indexed BufferGeometry; for flat per-tile color, don't share vertices between tiles. Fan-triangulate each tile around its center: hexagon → 6 triangles (18 vertex slots), pentagon → 5.

```js
// tiles: array of {id, center:[x,y,z], boundary:[[x,y,z]...], color:[r,g,b]}
const positions = [], colors = [], faceToTile = [];
for (const t of tiles) {
  const c = t.center, b = t.boundary, n = b.length;
  for (let i = 0; i < n; i++) {
    const p1 = b[i], p2 = b[(i + 1) % n];
    positions.push(c[0],c[1],c[2], p1[0],p1[1],p1[2], p2[0],p2[1],p2[2]);
    for (let k = 0; k < 3; k++) colors.push(...t.color);
    faceToTile.push(t.id);
  }
}
const geom = new THREE.BufferGeometry();
geom.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
geom.setAttribute('color',    new THREE.Float32BufferAttribute(colors, 3));
geom.computeVertexNormals();
const mesh = new THREE.Mesh(geom, new THREE.MeshStandardMaterial({vertexColors: true, flatShading: true}));
```
Keep `faceToTile` + `tileVertexRange[tileId] = {start, count}` for recoloring single tiles in place.

### 2.2 Picking
- **Raycaster (sufficient):** `raycaster.intersectObject(mesh)` → `intersection.faceIndex` → `faceToTile[faceIndex]`. Fine on click and throttled hover at ~60k triangles. Add three-mesh-bvh (`geom.computeBoundsTree()`) if hover raycasts get heavy.
- **GPU color-picking (upgrade):** render tileId-as-RGB to an offscreen WebGLRenderTarget, `readRenderTargetPixels` 1×1 at cursor. Constant cost, but stalls the pipeline — only on click/throttled hover.

### 2.3 Camera
```js
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
const controls = new OrbitControls(camera, renderer.domElement);
controls.enablePan = false; controls.enableDamping = true;
controls.minDistance = radius * 1.2; controls.maxDistance = radius * 4;
```

### 2.4 Vendoring three.js WITHOUT npm
Current three.js: ~0.185.x (r185). Core ESM: `build/three.module.js` (~150 KB min+gzip); addons under `examples/jsm/` via `three/addons/*` alias.
- **Option A (matches repo convention):** vendor `three.module.js` + `OrbitControls.js` into `assets/vendor/three/`; fix OrbitControls' bare `'three'` import (edit one line to relative, or add esbuild `--alias:three=./vendor/three/three.module.js`).
- **Option B:** `npm install three --prefix assets` (introduces package.json/node_modules the project has avoided).
- Consider lazy `import()` in the hook's `mounted()` to keep three out of the initial bundle.

## 3. LiveView integration pattern

### 3.1 Colocated hooks (Phoenix 1.8 / LiveView 1.1)
- Defined in HEEx as `<script :type={Phoenix.LiveView.ColocatedHook} name=".HexGlobe">`; name's leading dot is prefixed with the module name at compile time. Extracted at compile time into `phoenix-colocated/<app>`, bundled by esbuild (so imports work). The `ColocatedJS` runtime variant is NOT bundled — don't use for three.js.
- For a large renderer prefer a regular file hook (`assets/js/hooks/hex_globe.js`) merged into the hooks map.
- DOM anchor: `<div id="globe" phx-hook=".HexGlobe" phx-update="ignore" data-seed=... data-freq=...>`. **`phx-update="ignore"` is critical** so LiveView never patches the canvas subtree.

### 3.2 Data transport
1. `data-*` attributes — small static config (radius, seed, frequency).
2. `push_event/3` + `handleEvent` — bulk terrain/color payload after mount; streaming tile updates.
3. Client → server: `this.pushEvent("select_tile", {tile_id})` from the pick handler; sidebar assigns re-render normally outside the ignored subtree.

### 3.3 Payload size & the Elixir/JS split
- Full geometry for 10k tiles: ~21 floats/tile → **~2.5–4 MB JSON** or ~860 KB packed Float32. Terrain index only: **1 byte/tile → ~10 KB**.
- **Key insight: geometry is 100% deterministic from (radius, frequency)** — only terrain depends on seed. So: generate geometry client-side (hexasphere.js), send only a compact terrain/color array from Elixir via push_event (~10–30 KB); on regenerate, push a new color array and recolor the buffer in place.
- **Critical contract:** deterministic tile ordering must match between Elixir terrain array and JS geometry (tile N ↔ same tile).

## 4. Libraries
- **hexasphere.js (arscan)** — pure JS, no three.js dependency; `new Hexasphere(radius, subDivisions, tileWidth)`; `tiles[]` with `centerPoint`, `boundary`, `neighbors`; `toObj()`/`toJson()`. Directly usable; small enough to vendor.
- geodesic-dome (liammills), SergeySave/hexasphere, Rust generators — alternatives/reference.
- **H3 (Uber) is NOT this** — geospatial DGGS indexing, not a renderable Goldberg mesh.

## 5. Performance guidance
- f=16 → 2,562 tiles ≈ 15k tris; f=32 → 10,242 tiles ≈ 61k tris / ~184k verts non-indexed. Both trivial in 1 draw call; f=48 (~140k tris) still comfortable.
- No per-frame updates needed: terrain static, rotation = camera matrix. Can render on-demand (only when controls change) to save battery.
- Mobile: cap f=32, `renderer.setPixelRatio(Math.min(devicePixelRatio, 2))`, throttle hover raycasts.

## 6. Why per-frame SVG/CSS re-projection fails (for SMOOTH rotation)
- f=32 leaves ~5k visible polygons after backface culling; recomputing and rewriting 5k `points` attributes per frame → single-digit fps. No depth buffer → manual back-to-front sorting. Viable only ~f≤8 (~650 tiles) as low-fidelity fallback.
- (Stepped rotation sidesteps all of this — one re-render per step, like the existing pan.)

## Sources
- https://github.com/arscan/hexasphere.js/ · https://www.robscanlon.com/hexasphere/
- https://threejs.org/docs/ (BufferGeometry, InstancedMesh, Raycaster)
- https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.ColocatedHook.html
- https://www.phoenixframework.org/blog/phoenix-liveview-1-1-released
- GPU picking: https://github.com/bzztbomb/three_js_gpu_picking
- https://discoverthreejs.com/book/introduction/get-threejs/
