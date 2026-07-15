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
    mountain: "/images/game/decor/mountain.png",
    hills: "/images/game/decor/hills.png",
    woods: "/images/game/decor/woods.png",
    rainforest: "/images/game/decor/rainforest.png",
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
        patterns[key].setTransform(new DOMMatrix([k, 0, 0, k, px, py]))
        return patterns[key]
      },
    }
  },

  // Billboard: a sprite standing upright at a projected point, feet a
  // little below center so it sits ON the tile.
  drawBillboard(ctx, img, px, py, size, footBias = 0.62) {
    ctx.drawImage(img, px - size / 2, py - size * footBias, size, size)
  },
}

window.GlobeRender = GlobeRender
export default GlobeRender
