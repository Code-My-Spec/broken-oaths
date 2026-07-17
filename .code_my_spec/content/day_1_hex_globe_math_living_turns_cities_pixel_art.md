# Day 1 building Broken Oaths: hex globe math, living turns, cities, and pixel art

Quick recap from day 0: I'm building Broken Oaths, a massively multiplayer 4X where losing doesn't end your game. Your conqueror vassalizes you instead: you pay tribute, fight in their wars, and plot coordinated rebellions with the other vassals. Civ-style hexes, EU-style always-running time, multiple worlds, eventually god players.

Day 0 was a world-builder tech demo. Since then it became an actual game. Here's what shipped, with the technical details I skipped last time.

It's actually been 2 days but I lost one because Fable ran me dry by Tuesday.

## The hex globe math

You cannot tile a sphere with hexagons. Euler's formula forces exactly 12 pentagons, so the world is a Goldberg polyhedron: subdivide an icosahedron's faces, project the vertices onto the unit sphere, take the dual. Every tile is a hexagon except the 12 original icosahedron vertices, which become pentagons (I force them to impassable mountains; they're cursed and I like it that way).

The production globe runs at frequency 54: 10×54² + 2 = 29,162 tiles. Everything derives from one integer seed. Terrain comes from 3D fractal noise sampled at each tile's unit-sphere coordinates (no 2D projection, so no seams and no polar pinching): a base, relief, and features per tile.

Spawn placement partitions land into ~250-tile regions, and players only spawn into regions with room for ~7 cities. Same seed, same planet, every time. The server stores a seed and deltas, not 29k tiles.

## The renderer (no WebGL, still 3D)

Zero WebGL, zero JS frameworks. The globe started as a CSS 3D experiment (every tile a matrix3d div; it works and still lives behind a query param) and settled on a 2D canvas doing the projection by hand: orthographic math, backface culling by dot product, painter's-order fills. Far zoom switches to a per-pixel warp of a pre-baked planet texture, with clouds sampled on a second sphere shell for real parallax.

LiveView owns all game state; the canvas hook just paints what the server pushes. The client literally cannot know what's under the fog, because hidden tiles never travel over the wire. That's also why right-clicking into fog sends the clicked point on the sphere, and the server resolves which tile you meant.

## New since day 0

Living turns. Turns tick every 60 seconds, forever. Worlds keep running while you sleep, and a dormant world fast-forwards through every missed turn when it wakes.

Units and movement. Lords, settlers, warriors, workers. Orders execute immediately with whatever movement you have; the boundary just recharges points and continues queued paths. Server-side BFS pathing, collision interrupts, paths into unexplored fog. Units slide between tiles, pending paths render as dashed routes, movers pulse.

Fog of war. Per-player visibility computed server-side. Two players in one world see two genuinely different planets.

Cities. Settlers found cities. A new city claims its tile plus 6 neighbors; each population point claims exactly one more, picked deterministically by yield. Food thresholds drive growth to the Stone Age cap.

Production. Queue units, watch banked progress per turn, overflow carries between items, reorder freely, abandon mid-build and forfeit the investment. Settlers cost a population point when they spawn. Workers build farms and mines over multiple turns; progress sticks to the tile, so an abandoned dig waits for the next shovel.

Art. A week ago this was flat colored polygons. Now: 16×16 pixel sprites authored as text pixel maps and compiled through headless Aseprite, drawn as billboards on the globe; AI-generated seamless ground textures pattern-filled into each tile and anchored so terrain travels when you pan; and seeded weather, a drifting cloud field with storm cells that flash lightning.

## The process

The whole game is requirement-first: every story goes through example mapping (me answering PM questions from my phone), becomes browser-driven BDD specs before implementation, then agents build until the specs go green. A real browser QA pass per feature with real clicks and real 60-second turns.

Stack: Elixir + Phoenix + LiveView, PostgreSQL, canvas 2D. Build tools: Claude Code + CodeMySpec.

Next up: barbarians, combat, and the tech tree. Then the vassalization mechanics that are the whole point.

Demo: https://broken-oaths.com. Free to play.
