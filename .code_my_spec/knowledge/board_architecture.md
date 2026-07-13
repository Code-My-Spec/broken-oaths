# Board Architecture & Testability Doctrine

As of 2026-07-13 (commit 885f330). This is the contract for all future gameplay work.

## The two rules

1. **JS never owns game state.** Hooks own the camera (yaw/pitch/scale) and pixels, nothing else. Every game-meaningful interaction is a LiveView event (`select_tile`, `select_at`, future move/build/fight events) against server-authoritative state.
2. **Everything must be LiveView-testable.** Game logic tests never depend on a renderer. Two blessed entry points (helpers in `test/support/globe_helpers.ex`):
   - **Classic mode = the selector-testable board.** Tiles are server-rendered divs with `phx-value-id`. `camera_on(world, tile_id)` builds URL params that put ANY tile on screen; `click_tile(view, id)` clicks it with a selector. Full `element/2`-style testing.
   - **Globe mode = the production renderer, tested through its events.** `look_at(view, world, tile_id)` = a settled drag (`view_sync`); `select_tile_at(view, world, tile_id)` = a canvas click (`select_at` with the tile's unit-sphere center). Identical server code paths to production clicks.

**Trap to remember:** DOM injected client-side (push_event + innerHTML, e.g. the css3d facet layer) is INVISIBLE to LiveViewTest selectors — only server-rendered elements exist in the test DOM. Never design a feature whose only observable surface is client-injected DOM.

## Renderers

| Mode | URL | Rendering | Interaction | Role |
|---|---|---|---|---|
| Classic | `/worlds/:id` | Server-rendered divs + inline clip-path, stepped camera | `phx-click` per tile | Default; the selector-testable board |
| Globe | `?mode=3d` | Canvas only: far = baked-texture warp (L0 half-res first paint → L1), near = vector polygon fills from pushed `[id, palette, center, corners...]` rows, dpr-sharp | unproject → `select_at`; selection ring via `data-selected-id` | The pretty one; 60fps, phone-proof, zero DOM tiles |
| CSS-3D | `?mode=3d&renderer=css3d` | matrix3d facet divs (windowed, innerHTML-pushed) | client highlight + `select_tile` | Preserved experiment, URL-only |

## Camera in the URL

`?yaw=&pitch=&zoom=` (degrees / px-per-radius) set the initial camera in any mode, survive refresh, and are preserved across mode toggles. This is what makes deterministic test mounts possible.

## Perf invariants (learned the hard way)

- Hook-owned DOM (canvas, disc, tile layers) lives inside ONE `phx-update="ignore"` wrapper — LiveView patching hook-mutated elements causes an attribute war (canvas reset to 300×150 etc.).
- No CSS descendant selectors keyed on state classes (`.dragging .tile`) over thousands of 3D elements — one class toggle cost 31s of native style recalc.
- Tile windows/payloads bypass LiveView diffing (push_event), keyed by a view bucket (view direction ⊕ zoom band ⊕ seed ⊕ dims ⊕ device ⊕ renderer).
- Device tile budgets: `Projection.budget_theta/2` + `lod_k/3` (touch 1500 / desktop 7500) size the window and the canvas↔detail switchover.
- Texture bakes: `Worlds.Texture` equirect palette PNGs per (seed, frequency, level), pixel→tile index cached per frequency, warmed at boot.
