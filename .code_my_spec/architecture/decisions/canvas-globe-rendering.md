# Canvas impostor-first globe rendering, no WebGL

## Status
Accepted (implemented)

## Context
The globe must render ~29k tiles at 60fps in the browser — including
phones — while keeping every gameplay-relevant fact testable through
LiveViewTest. A WebGL renderer or client-side game framework would trade
away server authority and LiveView testability.

## Options Considered
- **WebGL (Three.js etc.)** — fastest rendering, but a parallel
  client-side world model, untestable from LiveViewTest, and against
  the PM's explicit constraint.
- **DOM tiles (divs + clip-path)** — works and stays selector-testable,
  but collapses at full-globe zoom (~30k nodes) and on touch devices.
- **CSS 3D (preserve-3d facets)** — validated experimentally; hits
  compositor layer limits and style-recalc cliffs (research:
  `css3d_deep_findings.md`).
- **Canvas impostor-first** — far zoom warps a server-baked
  equirectangular texture per-pixel into the orthographic disc; near
  zoom draws vector polygons from server-pushed geometry. Zero DOM
  tiles.

## Decision
Canvas impostor-first (the `?mode=3d` renderer), with the classic
server-rendered clip-path DOM renderer retained as the selector-testable
board. Doctrine (from `.code_my_spec/knowledge/board_architecture.md`):
**JS owns the camera and pixels only — never game state.** All game
facts flow server→client via `push_event` payloads and remain assertable
with `assert_push_event`; all interactions (select, view sync) are
LiveView events testable with `render_hook`. Hook-mutated DOM lives
inside a single `phx-update="ignore"` wrapper. Camera state lives in URL
params so tests can mount at any exact view.

## Consequences
- Two render paths to maintain (texture warp far, polygon fills near)
  plus the classic renderer; device tile budgets gate the switchover.
- Server bakes the world texture and windowed tile geometry
  (`Worlds.Texture`, `persistent_term`-cached, versioned keys).
- Future set pieces (units, cities) render as canvas sprites or
  2D-projected DOM billboards through the same camera math (research:
  `canvas_frontier.md`, `css3d_frontier.md`).
- Test helpers in `test/support/globe_helpers.ex` are the required
  interface for board tests.
