# Strategy-Game Presentation — Prior Art & Transferable Decisions

Research date: 2026-07-13. Companion to `board_architecture.md`, `hexasphere_geometry.md`, `hexglobe_webgl_rendering.md`.

Scope: what published strategy games do for globe/tile presentation, filtered to what transfers to **this** architecture — a Phoenix LiveView, server-authoritative Goldberg-polyhedron globe (f=54, 29,162 tiles, 12 pentagons), canvas renderer with a **far = baked equirect texture** view and a **near = vector-polygon** view across a zoom-dependent LOD handoff, plus a day/night cycle and drifting clouds. Everything cited.

---

## 0. Ranked "design decisions this project should steal"

Ordered by leverage (impact × how cleanly it drops into the existing architecture).

1. **Use the existing drifting-cloud layer AS fog-of-war for the unexplored state.** Cloud-cover-as-FoW is a proven idiom (Palworld's Sunreach; the popular "Alt FOW – Civ V Clouds" mod). It fuses an aesthetic you already render with a mechanic you need, and it hides the unexplored sphere without an ugly black void — critical because your far/texture view *shows the whole globe* (you cannot "just don't let them zoom out" the way flat-map games hide pentagons). Split the layer in two: **cosmetic drift stays client-side; the exploration mask is server-authoritative game state.** [§3, §7]

2. **Adopt Endless Legend's "info-morphing" as the explicit contract for your texture↔vector LOD handoff.** As you zoom out, per-tile detail should not shrink — it should *change kind*: 3D/vector tiles → flat cartographic icons; tile yields and features drop out; only POI/city/unit markers survive, at a clamped minimum pixel size. Your LOD boundary already exists; this gives it a design language instead of ad-hoc scaling. [§2]

3. **Keep pentagons as impassable mountains — and lean into it as the answer to Civ's "spheres are unfair" objection.** Civ stayed cylindrical because mixed pentagons/hexagons make tiles strategically unequal and complicate every algorithm. Making the 12 pentagons **impassable mountain massifs at fixed poles/rings** means no gameplay decision ever happens *on* a pentagon, so the fairness objection evaporates. Before We Leave shipped exactly this (hexasphere with pentagons hidden under mountains/oceans). You already do it; treat it as validated, and give those 12 sites deliberate "natural landmark" art. [§1]

4. **Store rivers as edges, roads/paths as centers (the T-machine hybrid).** Your Goldberg mesh already carries explicit corner/edge adjacency (`neighbors[i]` edge lies between `corners[i]` and `corners[i+1]`), so edge-based rivers — Civ's model — map in for free: a river is a canonicalized `(min_id, max_id)` edge pair, rendered as a stroke along the shared corner segment. Movement/combat penalties and freshwater bonuses attach to the edge. Roads and unit move-paths stay center-to-center for connectivity legibility. [§5]

5. **Render terrain features as near-view-only sprite scatter, deterministic from tile id.** Civ 6 composes base × feature as overlays; you already compose base × relief × feature into one color. Add features as a *near/vector-only detail layer*: hash the tile id to scatter N tiny deterministic glyphs (tree dots, marsh reeds) inside the polygon, and fake relief with a lightened top-edge / darkened bottom-edge on the tile. The far/texture view keeps only the composed color. [§4]

6. **Make the overview a rotating mini-globe that mirrors the main camera, not an equirect minimap.** An equirectangular minimap distorts exactly where your interesting singularities live (poles = pentagons + ice). A small globe that reuses your already-baked far texture is nearly free to render and reads correctly at the poles; click-to-navigate = unproject the click to lat/lon → set `yaw/pitch` (URL params already support this). [§6]

7. **Three-state fog of war with a server-held per-player visibility set; "explored-not-visible" = desaturated last-known terrain.** The StarCraft/AoE standard (unexplored / explored-dim / visible-full) is what players expect. Because your palette is server-pushed per view-bucket, the server can push a **per-player masked palette** (desaturated for explored-not-visible), keeping visibility authoritative and LiveView-testable per your doctrine. [§3, §7]

8. **Hold the cosmetic/authoritative line you already drew.** Day/night and cloud *drift* are presentation → client animation, no round-trip. Everything a player decides on — selection, movement, exploration reveal — is a LiveView event against server state. This is the exact thin-client model boardgame.io and the general server-authoritative literature prescribe; your doctrine is already correct, so the only new rule is: when clouds double as FoW, keep the drift layer (cosmetic) separate from the exploration mask (authoritative). [§7]

---

## 1. Spherical / global tile boards

**The universal constraint.** You cannot tile a sphere with only regular hexagons; subdividing an icosahedron leaves exactly 12 pentagons (Euler). Every serious attempt confronts these 12 singularities. ([Red Blob – Wraparound hex maps on a sphere](https://www.redblobgames.com/x/1640-hexagon-tiling-of-sphere/))

**Why Civ itself stayed a cylinder.** Civ maps wrap east–west but hard-stop north–south — topologically a cylinder, with polar ice hiding the discontinuity. The stated reasons are *gameplay fairness* (all tiles must have equal neighbor counts or locations aren't "strategically identical") and *engine simplicity* (every pathfinding/distance/area algorithm assumes a regular grid; pentagons break them). ([CivV Steam discussion](https://steamcommunity.com/app/8930/discussions/0/1471966894860843148/), [Red Blob](https://www.redblobgames.com/x/1640-hexagon-tiling-of-sphere/))

**How shipped games resolve the 12 pentagons:**
- **Before We Leave** (Balancing Monkey Games) ships a real hexasphere and **hides the pentagons under mountains and oceans** — the player never makes a decision on one. ([Red Blob](https://www.redblobgames.com/x/1640-hexagon-tiling-of-sphere/), [Wikipedia](https://en.wikipedia.org/wiki/Before_We_Leave))
- **Red Blob's** general advice: hide pentagons by *restricting access* (don't let the player walk near them) — but explicitly warns this "only works in games where you're walking/driving and not games where you can zoom out." A zoom-out-to-globe game must handle them visually. ([Red Blob](https://www.redblobgames.com/x/1640-hexagon-tiling-of-sphere/))
- A long CivFanatics thread proposing an **octahedron** base (6 overlap-sites instead of 12 pentagons) collapsed under exactly the fairness objections Civ feared — unequal k-neighborhoods near the artifacts, and 4-tile vertices recreating Civ IV's diagonal-shortcut exploits. Validates *not* going down that road; the icosahedral-Goldberg + impassable-pentagon choice is the sound one. ([CivFanatics: The Globe in Civ V](https://forums.civfanatics.com/threads/solution-the-globe-in-civ-v-a-really-spherical-map-with-only-hexagonal-tiles.356334/))

**Transfer to this project.** You already mark the 12 pentagons `mountains / impassable`. That single move simultaneously (a) neutralizes the fairness objection — no gameplay happens on a defect, and (b) turns the singularity into a *feature*, not a bug: 12 fixed mountain landmarks (polar ones are Snow Mountains). Since your far view renders the whole globe, don't try to *hide* them — give them intentional art so they read as natural massifs.

**Pole & camera UX — the real remaining hazard.** Crossing a pole does **not** wrap to the antipode; you keep position but your facing reverses, and circumnavigating near a pole covers less ground than at the equator. Red Blob's mitigation is to *rotate the camera to keep the local area upright and constrain what you can see near the pole*. ([Red Blob](https://www.redblobgames.com/x/1640-hexagon-tiling-of-sphere/)) For your yaw/pitch camera this is a gimbal-lock problem at `pitch = ±90°`: define explicit pole behavior (clamp pitch just short of the pole, or switch to a quaternion/great-circle camera) so dragging over a pole doesn't flip or spin. This is the single UX detail most globe prototypes get wrong.

---

## 2. Multi-zoom unit/building representation & the LOD handoff

This is the topic that maps most directly onto your texture↔vector boundary.

**Endless Legend — "info-morphing" (the model to copy).** As the player zooms out, the *representation of a hex's information changes* — it becomes "simpler and more iconographic," and past a threshold the 3D adventure map flips to a flat 2D cartographic view. Tile-yield numbers vanish when zoomed out; higher-salience markers (city status, points of interest) persist. The critique literature also flags the failure modes: the zoomed-out view can look bare, and low-contrast overlays (white order-arrows on snow) disappear. ([Making Games: UI of Endless Legend](https://www.makinggames.biz/feature/making-of-the-user-interface-in-endless-legends,9338.html) via search snippet; [Any Key To Start critique](https://anykeytostart.wordpress.com/2015/04/22/endless-legend/))

**Civ 6 — Strategic View as a distinct visual language.** Civ 6's zoomed-out mode is a deliberately *designed 2D icon representation* (built/implemented by designer Sam Gauss), not merely the 3D scene shrunk. It drops animated unit/building models for flat icons to keep a busy map legible. ([Sam Gauss / ArtStation](https://www.artstation.com/artwork/bZqrd), [gamepressure Civ6 interface guide](https://guides.gamepressure.com/sidmeierscivilization6/guide.asp?ID=37562))

**The readability failure to avoid.** Civ 6's most-cited icon complaint: icons that **don't rescale with zoom cover too much of the tile**, and multiple icons on one hex (unit + resource + improvement) overlap instead of taking distinct slots (a regression from Civ 5's fixed positions). ([CivFanatics: strategic view](https://forums.civfanatics.com/threads/strategic-view.572168/), [smaller icons thread](https://forums.civfanatics.com/threads/smaller-resource-unit-icons.605066/))

**Transfer to this project (tiles at 15–40px):**
- **Don't shrink assets across the handoff — swap representation kind.** Far/texture view = strategic icons + POI/unit markers only, no per-tile chrome. Near/vector view = full tile fills, feature scatter, relief shading, unit sprites. The two already agree on tile color (your palette is composed identically for canvas payloads and texture PLTE), so a **crossfade** between them will look continuous.
- **Clamp marker screen size.** Give unit/city glyphs a *minimum and maximum* pixel size independent of zoom (Civ 6's bug is the absence of this). At 15–40px tiles, a glyph should occupy a fixed fraction of the tile and never grow to cover it.
- **Assign fixed icon slots per tile** (e.g. unit = center, resource = top-right, improvement = bottom) so stacked information never overlaps — the thing Civ 5 did and Civ 6 lost.
- **De-clutter by aggregation** when zoomed out: collapse a stack/army to a single count badge rather than N overlapping sprites.

---

## 3. Fog of war & exploration on tile boards

**The expected three states** (StarCraft, Age of Empires, and essentially every 4X): (1) **unexplored** — hidden; (2) **explored but not currently visible** — dimmed/desaturated, showing *last-known* terrain (and stale enemy positions); (3) **visible** — full color, live. StarCraft's phrasing: unseen areas are dark; once discovered they stay visible but turn grey when no friendly unit is present. ([Wikipedia: Fog of war](https://en.wikipedia.org/wiki/Fog_of_war), [TV Tropes: Fog of War](https://tvtropes.org/pmwiki/pmwiki.php/Main/FogOfWar))

**Visual treatments in tile games.** The common tile approach is a **masked overlay whose alpha/color is modulated per tile** — desaturation and dimming for explored-not-visible, full opacity for unexplored — with edge-smoothing and fade transitions between states so the boundary animates rather than snaps. ([Didac Romero: tile FoW in SDL](https://didacromero.github.io/Fog-of-War/), [DidacRomero/Fog-of-War](https://github.com/DidacRomero/Fog-of-War))

**Cloud cover as fog of war.** Clouds are a shipped idiom for the *unexplored* veil specifically: Palworld hides the Sunreach region under clouds until you find its watchtower; the "Alt FOW – Civ V Clouds" mod replaces the black unexplored mask with cloud cover. ([Palworld cloud FoW](https://gamerant.com/palworld-how-remove-fog-of-war-cloud-sunreach-floating-island-reveal-map/), [Civ V Clouds FoW mod](https://steamcommunity.com/sharedfiles/filedetails/?id=1286146406))

**Transfer to this project (the highest-leverage idea):**
- **Your drifting clouds already exist — make them the unexplored veil.** Unexplored tiles sit under (denser) cloud; exploring thins/parts the cloud over them. This avoids a black void on a globe you can see in full from the far view.
- **Data model:** per-player `explored` set and `visible` set on the server (authoritative, testable — fits your doctrine). Reveal/visibility changes are game state, driven by LiveView events, never client-guessed.
- **Rendering split (important):** keep two distinct layers. **Cloud drift** = cosmetic, animated client-side, no round-trip. **Exploration mask** = server-authoritative; the cloud density/opacity per tile is *driven by* the mask but the drift animation is not. Don't let the pretty animation own the mechanic.
- **Explored-not-visible = desaturated composed color.** Because the server already pushes per-view-bucket palettes, it can push a **per-player masked palette** (desaturated entries for explored-not-visible tiles), so the dimming is authoritative rather than a client filter that could disagree with server truth. Near view can additionally show *stale* last-known units; far view just desaturates.

---

## 4. Terrain-feature rendering in hex games

**Civ 6's model = yours.** Civ 6 separates base terrain from **features** (Woods, Rainforest, Marsh, Floodplains…) drawn *on top of* the base, and features can be added/removed independently during play (chop the woods, drain the marsh). ([Terrain (Civ6)](https://civilization.fandom.com/wiki/Terrain_(Civ6)), [Woods (Civ6)](https://civilization.fandom.com/wiki/Woods_(Civ6))) This is exactly your `base × relief × feature` struct with an independently-mutable feature slot — validated as the right decomposition.

**Cheap 2D/canvas equivalents (near-view detail layer only):**
- **Tint** — you already do this (feature overlays base, relief shades through, one composed color). This alone carries the far/texture view.
- **Sprite scatter for features** — at near/vector zoom, stamp small semi-random glyphs inside the tile polygon: tree dots for woods, denser darker dots for rainforest, reed/hatch marks for marsh. Make it **deterministic**: seed the scatter from a hash of the tile id so it's stable across frames and identical on every client (no server payload needed — geometry + id are already known client-side, same trick your renderer uses for tile windows).
- **Relief without 3D** — fake elevation with edge shading: lighten the sun-facing top edge and darken the lower edge of a hill/mountain tile's polygon, or stamp a small chevron/bump glyph. Cheap, reads instantly, and can key off your day/night sun direction for consistency.
- **Keep it LOD-gated.** Features and relief detail are a *near-view-only* layer; the far/texture view stays flat composed color. This matches your existing texture↔vector split and keeps the far view cheap.

---

## 5. Rivers in hex games

**Civ runs rivers along hex EDGES, not tile centers.** Gameplay consequences: crossing a river-edge costs movement and imposes a combat penalty; river-adjacency grants freshwater/food/housing bonuses to *both* banks. ([T-machine: roads/rivers, center vs edge](https://t-machine.org/index.php/2016/04/18/the-age-old-question-of-civ-games-roads-and-rivers-in-center-of-tiles-or-edges/), [Humankind forum: rivers on edges](https://community.amplitude-studios.com/amplitude-studios/humankind/forums/169-game-design/threads/40032-why-aren-t-rivers-at-the-edge-of-tiles))

**Center vs edge — the tradeoff (T-machine's analysis):**
- *Center:* "straight" things (canals, big navigable rivers, roads), trivial movement rule ("on the tile = on the road"), but needs artificial wiggle to look natural in 3D and blurs which tiles a road actually connects.
- *Edge:* meandering, realistic, gives the clean cross-penalty mechanic — but historically *blocked river navigation* (no code to move a boat that lives on an edge) and creates connectivity ambiguity.
- **Recommendation: hybrid — rivers on edges, roads on centers.** Plus a movement shortcut: a unit adjacent to a road/river inherits its benefit, buying connectivity "for free." ([T-machine](https://t-machine.org/index.php/2016/04/18/the-age-old-question-of-civ-games-roads-and-rivers-in-center-of-tiles-or-edges/))

**Data-model note.** A practical Civ-style storage trick: each cell records only its **W, SW, SE edges** (a cell's E edge is its east neighbor's W edge), so every edge is stored once. ([Nick Chavez: hex map design](https://nicolaschavez.com/projects/hex-map-design/))

**Transfer to this project (rivers map in almost for free):**
- Your mesh already guarantees `neighbors[i]`'s shared edge lies between `corners[i]` and `corners[i+1]`. So a **river = a set of edges**, each stored canonically as a sorted `(min_id, max_id)` tile pair (the exact dedup convention your adjacency generation already uses — no double storage, no per-cell W/SW/SE bookkeeping needed because you have explicit corner rings).
- **Render (near/vector view):** stroke a polyline along the shared corner segment(s) of each river edge; widen with river "order" if you model tributaries. Far/texture view: bake major rivers into the equirect PNG or omit.
- **Gameplay:** attach the move/combat penalty and freshwater bonus to the edge; freshwater applies to both incident tiles.
- **Roads/paths:** center-to-center polylines (`neighbors` graph), consistent with unit move-path rendering — the readable half of the hybrid.
- **Caveat to design around:** if you ever want river-boat movement, decide up front whether boats traverse the edge-graph (dual of tiles) or hug river tiles — the classic Civ trap was bolting it on afterward.

---

## 6. Minimap / overview UX for globes

**The two options.** A **rotating mini-globe** (drag to spin, wheel to zoom, click-to-navigate) versus an **equirectangular minimap**. Equirect is cheap and familiar but **distorts badly at the poles** — precisely where your pentagons and polar ice sit. ([Mini-map (Wikipedia)](https://en.wikipedia.org/wiki/Mini-map), [amCharts rotating globe](https://www.amcharts.com/demos/rotating-globe/), [globe.gl](https://github.com/vasturiano/globe.gl))

**Click-to-navigate convention.** Interactive globe components standardly expose a click callback carrying the clicked lat/lon, used to recenter/fly-to. ([globe.gl](https://github.com/vasturiano/globe.gl))

**Transfer to this project:**
- **Use a rotating mini-globe, not equirect** — it reads correctly at the poles and can **reuse your already-baked far texture** rendered at tiny size, so it's nearly free.
- **Mirror the main camera:** the mini-globe's orientation tracks `yaw/pitch`; the visible-hemisphere or a reticle shows where you're looking.
- **Click-to-navigate:** unproject the mini-globe click to lat/lon → set `yaw/pitch` (your URL already carries these, so navigation is a camera assign, deterministic and refresh-survivable).
- Because you *also* bake equirect PNGs, an equirect strip is available for free as a secondary "map mode" if wanted — but treat the globe as primary and never put pole-sensitive UI on the equirect.

---

## 7. Turn/real-time presentation over server-authoritative state (LiveView fit)

**The thin-client consensus.** Server is the single source of truth: it validates moves, runs game logic, and broadcasts state; clients only render and handle local interaction and are never authoritative. Keeping logic server-side means rules change without client redeploys. boardgame.io codifies this — describe state on the server, get synced multiplayer clients for free. ([boardgame.io](https://boardgame.io/), [DEV: multiplayer board game with WebSockets](https://dev.to/krishanvijay/building-a-multiplayer-board-game-with-javascript-and-websockets-4fae), [Game server architecture basics](https://techtidesolutions.com/blog/game-server-architecture-basics/))

**Turn-based specifics.** Enforce one actor at a time; broadcast state deltas as events to everyone in the room — a natural fit for LiveView + Phoenix PubSub. ([boardgame.io](https://boardgame.io/))

**Transfer to this project — you're already aligned; two refinements:**
- Your doctrine ("JS never owns game state; hooks own only camera + pixels; every game-meaningful interaction is a LiveView event") *is* the thin-client model the literature prescribes. No change of direction needed — this section is validation.
- **Draw the cosmetic/authoritative line explicitly and keep it:** day/night cycle and cloud *drift* are presentation → pure client animation, zero round-trips (correct as-is). Selection, movement, build, and **exploration reveal** are game state → server events. The one new hazard introduced by §3 (clouds doubling as FoW): the cloud *animation* stays client cosmetic, but the *exploration mask that decides cloud opacity per tile* is server-authoritative — don't let the animation layer silently become the source of truth for what's explored.
- **Testability corollary (your doctrine's trap):** anything whose only surface is client-injected DOM/canvas is invisible to LiveViewTest. So FoW state, unit positions, and river/edge state must be observable through server-rendered elements or server-pushed payloads keyed to testable events — never inferred solely from canvas pixels.

---

## Sources

Spherical boards / pentagons / poles:
- Red Blob Games — Wraparound hexagon tile maps on a sphere: https://www.redblobgames.com/x/1640-hexagon-tiling-of-sphere/
- CivV Steam — "So, maps are cylindrical?": https://steamcommunity.com/app/8930/discussions/0/1471966894860843148/
- CivFanatics — "Solution: The Globe in Civ V…": https://forums.civfanatics.com/threads/solution-the-globe-in-civ-v-a-really-spherical-map-with-only-hexagonal-tiles.356334/
- Before We Leave — Wikipedia: https://en.wikipedia.org/wiki/Before_We_Leave

Multi-zoom / LOD / strategic view:
- Making Games — UI of Endless Legend ("info-morphing"): https://www.makinggames.biz/feature/making-of-the-user-interface-in-endless-legends,9338.html
- Any Key To Start — Endless Legend interface critique: https://anykeytostart.wordpress.com/2015/04/22/endless-legend/
- Sam Gauss — Civilization 6 Strategic View (ArtStation): https://www.artstation.com/artwork/bZqrd
- gamepressure — Civ 6 interface guide: https://guides.gamepressure.com/sidmeierscivilization6/guide.asp?ID=37562
- CivFanatics — Strategic View thread: https://forums.civfanatics.com/threads/strategic-view.572168/

Fog of war:
- Wikipedia — Fog of war: https://en.wikipedia.org/wiki/Fog_of_war
- TV Tropes — Fog of War: https://tvtropes.org/pmwiki/pmwiki.php/Main/FogOfWar
- Didac Romero — Tile-based Fog of War (SDL/C++): https://didacromero.github.io/Fog-of-War/
- Palworld cloud FoW: https://gamerant.com/palworld-how-remove-fog-of-war-cloud-sunreach-floating-island-reveal-map/
- Civ V Clouds FoW mod: https://steamcommunity.com/sharedfiles/filedetails/?id=1286146406

Terrain features:
- Civ6 Terrain: https://civilization.fandom.com/wiki/Terrain_(Civ6) · Woods: https://civilization.fandom.com/wiki/Woods_(Civ6)

Rivers / edges:
- T-machine — roads/rivers, center vs edge: https://t-machine.org/index.php/2016/04/18/the-age-old-question-of-civ-games-roads-and-rivers-in-center-of-tiles-or-edges/
- Humankind forum — rivers on edges: https://community.amplitude-studios.com/amplitude-studios/humankind/forums/169-game-design/threads/40032-why-aren-t-rivers-at-the-edge-of-tiles
- Nick Chavez — Hex strategy map design (edge storage): https://nicolaschavez.com/projects/hex-map-design/

Globe minimap / overview:
- Wikipedia — Mini-map: https://en.wikipedia.org/wiki/Mini-map
- amCharts rotating globe demo: https://www.amcharts.com/demos/rotating-globe/
- globe.gl (Vasco Asturiano): https://github.com/vasturiano/globe.gl

Server-authoritative / thin client:
- boardgame.io: https://boardgame.io/
- DEV — Multiplayer board game with JS + WebSockets: https://dev.to/krishanvijay/building-a-multiplayer-board-game-with-javascript-and-websockets-4fae
- Game server architecture basics: https://techtidesolutions.com/blog/game-server-architecture-basics/

Paradox map modes (reference for map-mode layering):
- Green Man Gaming — Imperator: Rome map feature: https://www.greenmangaming.com/intel-feature/paradox/imperator-rome-map/
