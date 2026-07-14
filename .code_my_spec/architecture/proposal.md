# Architecture Proposal

Batch 1 — the gameplay substrate. Five stories mapped onto one new
domain context (`BrokenOaths.Game`), one new child in the existing
static-world context (`BrokenOaths.Worlds.Regions`), and one new
surface live-context (`BrokenOathsWeb.GameLive`). Grounded in the ADRs:
world-process-architecture (GenServer per world, in-process 60s tick,
LiveViews as PubSub-fed projections), game-state-persistence
(delta-over-seed), and canvas-globe-rendering (JS owns camera only;
every game fact server-owned and LiveView-testable).

The existing `BrokenOaths.Worlds` context stays the pure, static world:
mesh, terrain, projection — everything derivable from the seed. The new
`BrokenOaths.Game` context owns everything mutable: players, units,
orders, turns, exploration. Fog-of-war filtering happens server-side per
player; hidden tiles never reach a client.

## Contexts

### BrokenOaths.Worlds

- **Type:** context
- **Description:** Static, seed-derived world: Goldberg mesh, terrain generation, projection math, textures — and now the deterministic region partition that divides the globe into player territories. Pure functions of the seed; nothing here mutates during play.
- **Stories:** 877

#### Children

- BrokenOaths.Worlds.Regions (module) [Stories: 877]: Deterministic partition of the globe into ~250-tile player regions (seed-derived), with region adjacency and boundary tiles; world capacity = region count

### BrokenOaths.Game

- **Type:** context
- **Description:** The live game running on a world: player membership and spawning, units, queued orders, the 60-second turn pipeline, and per-player exploration/visibility. One WorldServer process per world serializes all mutation and broadcasts coalesced diffs over PubSub; persistence is the mutable delta over the world seed.
- **Stories:** 873, 874, 875, 876, 877

#### Children

- BrokenOaths.Game.Player (schema) [Stories: 873, 877]: A user's presence in a world — claimed region, gold, joined-at turn
- BrokenOaths.Game.Unit (schema) [Stories: 873, 875]: A unit on the board — type (lord/settler), owner, tile id, hp, movement points
- BrokenOaths.Game.Order (schema) [Stories: 875]: A queued order for the next turn boundary — unit, kind (move), target tile, validation state
- BrokenOaths.Game.Exploration (schema) [Stories: 876]: Per-player explored-tile mask for a world, persisted as part of the delta
- BrokenOaths.Game.WorldServer (module) [Stories: 874]: GenServer, one process per world (Registry-addressed, lazily started) — owns live state, runs the send_after turn tick, applies commands, broadcasts diffs
- BrokenOaths.Game.Turn (module) [Stories: 874]: Pure turn pipeline — tick(state) resolves queued orders simultaneously, advances the turn counter; property-testable without processes
- BrokenOaths.Game.Spawner (module) [Stories: 873, 877]: Spawn placement — claims an open region, picks a valid start tile (terrain-checked, far from neighbors), creates the starting Lord + Settler and 50 gold
- BrokenOaths.Game.Visibility (module) [Stories: 876]: Pure fog-of-war math — vision radii per unit type (Lord sees farther), three-state tile visibility (unexplored / explored / visible), per-player world filtering

## Surface Components

### BrokenOathsWeb.GameLive

- **Type:** live_context
- **Description:** The play surface — joining a world and playing on the hex globe board. Holds only a projection of WorldServer state: subscribes to the world's PubSub topic, sends commands, re-windows the fog-filtered board on diffs. Reuses the existing canvas globe renderer; every gameplay fact stays assertable through LiveViewTest.
- **Stories:** 873, 874, 875, 876, 877

#### Children

- BrokenOathsWeb.GameLive.Play (liveview) [Stories: 873, 874, 875, 876]: The board — fog-filtered globe with units, unit selection, order queueing, live turn updates, camera centered on spawn
- BrokenOathsWeb.GameLive.Join (liveview) [Stories: 873, 877]: Enter the game — find/create an active world with an open region, claim it, spawn, redirect to Play
- BrokenOathsWeb.GameLive.TurnBar (liveview_component) [Stories: 874]: Turn number and 60-second countdown to the next turn boundary
- BrokenOathsWeb.GameLive.UnitPanel (liveview_component) [Stories: 875]: Selected unit details (type, HP, movement remaining) and its queued order

## Dependencies

- BrokenOathsWeb.GameLive -> BrokenOaths.Game
- BrokenOathsWeb.GameLive -> BrokenOaths.Worlds
- BrokenOaths.Game -> BrokenOaths.Worlds
- BrokenOaths.Game -> BrokenOaths.Users
