// Shared globe rendering core for the two canvas globe hooks —
// GameLive.Play (fog-filtered game board) and WorldLive.Show (world
// preview). The two views keep deliberately different data models and
// camera authorities (issue dd5f2867); what they share is the math and
// the art plumbing, and it lives here exactly once:
//
//   * orthographic projection / inverse projection for a {yaw, pitch,
//     scale, cx, cy} view
//   * polygon tracing for compact tile rows (corners at any radial
//     multiplier — terrain at 1.0/lift, cloud shells at ALT)
//   * the weather cloud palette (single source for both views)
//   * sprite + ground-texture preloading and zoom-anchored pattern fills
//
// Exposed as a window global (window.GlobeRender), matching the
// screenshot.js precedent — colocated hooks read it at mounted() time.

const GlobeRender = {
  // Precompute the frame's rotation terms once per draw.
  rot(view) {
    return {
      cyw: Math.cos(view.yaw),
      syw: Math.sin(view.yaw),
      cp: Math.cos(view.pitch),
      sp: Math.sin(view.pitch),
      S: view.scale,
      cx: view.cx,
      cy: view.cy,
    }
  },

  // World point -> screen. depth > 0 faces the camera.
  project(r, x, y, z) {
    return {
      px: r.cx + r.S * (-r.syw * x + r.cyw * y),
      py: r.cy - r.S * (-r.sp * r.cyw * x - r.sp * r.syw * y + r.cp * z),
      depth: r.cp * r.cyw * x + r.cp * r.syw * y + r.sp * z,
    }
  },

  depth(r, x, y, z) {
    return r.cp * r.cyw * x + r.cp * r.syw * y + r.sp * z
  },

  // Screen point -> unit-sphere world vector (null off the globe).
  unproject(view, sx, sy) {
    const vx = (sx - view.cx) / view.scale
    const vy = (view.cy - sy) / view.scale
    const r2 = vx * vx + vy * vy
    if (r2 > 1) return null
    const vz = Math.sqrt(1 - r2)
    const cyw = Math.cos(view.yaw), syw = Math.sin(view.yaw)
    const cp = Math.cos(view.pitch), sp = Math.sin(view.pitch)
    return {
      x: -syw * vx - sp * cyw * vy + cp * cyw * vz,
      y: cyw * vx - sp * syw * vy + cp * syw * vz,
      z: cp * vy + sp * vz,
    }
  },

  // Trace a tile row's corner polygon into the current path. `from` is
  // the index of the first corner coordinate in the row; `mult` lifts
  // the polygon radially (1.0 surface, ALT for cloud shells).
  tracePolygon(ctx, r, row, from, mult = 1.0) {
    for (let i = from; i < row.length; i += 3) {
      const x = row[i] * mult, y = row[i + 1] * mult, z = row[i + 2] * mult
      const px = r.cx + r.S * (-r.syw * x + r.cyw * y)
      const py = r.cy - r.S * (-r.sp * r.cyw * x - r.sp * r.syw * y + r.cp * z)
      if (i === from) ctx.moveTo(px, py); else ctx.lineTo(px, py)
    }
    ctx.closePath()
  },

  // Weather cloud palette — the single source both views derive from.
  // [r, g, b, alpha255] per level; Worlds.Weather mirrors these.
  CLOUD_BASE: {1: [250, 251, 253, 96], 2: [240, 244, 249, 175], 3: [104, 110, 124, 215]},

  // Flat (unshaded) rgba strings, e.g. for the game board.
  cloudFlat() {
    const out = {}
    for (const [lvl, [r, g, b, a]] of Object.entries(this.CLOUD_BASE)) {
      out[lvl] = `rgba(${r},${g},${b},${(a / 255).toFixed(3)})`
    }
    return out
  },

  // Cloud-shell altitude as a multiple of the surface radius.
  CLOUD_ALT: 1.035,

  // Billboard sprite + ground texture manifests (ADR game-art-pipeline).
  SPRITES: {
    lord: "/images/game/units/lord.png",
    settler: "/images/game/units/settler.png",
    warrior: "/images/game/units/warrior.png",
    bronze_spearman: "/images/game/units/bronze_spearman.png",
    // QA issue da39e50b "No archer" — placeholder art (a recolored
    // Warrior sprite, same "distinct tint" stopgap `bronze_spearman`
    // itself used); flag real bespoke Archer art as a follow-up.
    archer: "/images/game/units/archer.png",
    worker: "/images/game/units/worker.png",
    barbarian: "/images/game/units/barbarian.png",
    mountain: "/images/game/decor/mountain.png",
    hills: "/images/game/decor/hills.png",
    woods: "/images/game/decor/woods.png",
    rainforest: "/images/game/decor/rainforest.png",
    city: "/images/game/decor/city.png",
    camp: "/images/game/decor/camp.png",
    farm: "/images/game/decor/farm.png",
    mine: "/images/game/decor/mine.png",
    road: "/images/game/decor/road.png",
    pasture: "/images/game/decor/pasture.png",
    cattle: "/images/game/decor/cattle.png",
    sheep: "/images/game/decor/sheep.png",
    wheat: "/images/game/decor/wheat.png",
    stone: "/images/game/decor/stone.png",
    // Story 911 — Copper, the map's first STRATEGIC resource (Bronze
    // Spearman's access gate). Placeholder art: a straight copy of the
    // Stone decor sprite (same "rock on hills" silhouette) until a
    // bespoke Copper billboard exists — flagged for real art.
    copper: "/images/game/decor/copper.png",
  },

  TERRAIN_TEXTURES: ["grassland", "plains", "desert", "tundra", "snow", "ocean",
                     "coast", "woods", "rainforest", "marsh", "ice"],

  loadSprites(onload) {
    const out = {}
    for (const [key, path] of Object.entries(this.SPRITES)) {
      const img = new Image()
      img.onload = onload
      img.src = path
      out[key] = img
    }
    return out
  },

  loadTerrainTextures(onload) {
    const out = {}
    for (const key of this.TERRAIN_TEXTURES) {
      const img = new Image()
      img.onload = onload
      img.src = "/images/game/terrain/" + key + ".png"
      out[key] = img
    }
    return out
  },

  ready(img) {
    return img && img.complete && img.naturalWidth ? img : null
  },

  // Zoom-anchored repeating pattern pool. Patterns are anchored to each
  // tile's projected center so the texture travels with the tile
  // through pans and zooms instead of swimming in screen space.
  patternPool(textures) {
    const patterns = {}
    return {
      for(ctx, key, zoomScale, px, py) {
        const img = GlobeRender.ready(key && textures[key])
        if (!img) return null
        if (!patterns[key]) patterns[key] = ctx.createPattern(img, "repeat")
        const k = Math.max(zoomScale / 1400, 0.25)
        // QA issue 551f9a55 — the anchor itself was the other half of
        // the ripple (nearest-neighbor sampling in the board hook's own
        // `draw()` fixes the bilinear-resample half): `px`/`py` are the
        // tile's projected screen center, which drifts by sub-pixel
        // amounts every single frame during a pan/rotate. Snapping the
        // anchor to the nearest whole pixel removes that jitter — the
        // pattern still tracks the tile (the rounding error is under a
        // pixel, well below what's visible), it just stops "swimming".
        patterns[key].setTransform(new DOMMatrix([k, 0, 0, k, Math.round(px), Math.round(py)]))
        return patterns[key]
      },
    }
  },

  // Billboard: a sprite standing upright at a projected point, feet a
  // little below center so it sits ON the tile.
  drawBillboard(ctx, img, px, py, size, footBias = 0.62) {
    ctx.drawImage(img, px - size / 2, py - size * footBias, size, size)
  },

  // Boundary edges for a set of compact tile rows (QA issues
  // 759d02c8/0b8a75e4 — a selected city's own territory border):
  // the polygon edges that belong to exactly ONE tile in `rows` — an
  // edge shared by two tiles in the same set is an interior seam, not
  // a border. Row corner coordinates are already the server's own
  // `round4/1`'d floats, so two neighboring tiles' shared corner is
  // bit-identical — no epsilon matching needed, a plain string key is
  // exact. Returns `[[a, b], ...]`, each a pair of `[x, y, z]` world
  // points (not yet projected).
  computeBorderEdges(rows) {
    const count = new Map()
    const coords = new Map()

    for (const row of rows) {
      const corners = []
      for (let i = 7; i < row.length; i += 3) corners.push([row[i], row[i + 1], row[i + 2]])

      for (let i = 0; i < corners.length; i++) {
        const a = corners[i]
        const b = corners[(i + 1) % corners.length]
        const ka = a.join(","), kb = b.join(",")
        const key = ka < kb ? `${ka}|${kb}` : `${kb}|${ka}`
        count.set(key, (count.get(key) || 0) + 1)
        coords.set(key, [a, b])
      }
    }

    const edges = []
    for (const [key, n] of count) if (n === 1) edges.push(coords.get(key))
    return edges
  },
}

window.GlobeRender = GlobeRender
export default GlobeRender
