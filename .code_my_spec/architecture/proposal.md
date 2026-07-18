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

## Feudal Foundation Batch (stories 906–908)

The feudal vassalage foundation maps onto the **existing** `BrokenOaths.Game`
context (as new child modules/schemas) and the existing `BrokenOathsWeb.GameLive`
live-context (as new components) rather than a new top-level context. Rationale:
in this codebase everything mutable-on-a-world (units, cities, combat, research)
is a child of the single `Game` context, serialized by the WorldServer and
persisted via the tick delta — vassalage is the same kind of live state. A
separate `Vassalage` context would have to depend on `Game` (players, cities,
turn pipeline) while `Game` depends on it (Siege creates vassalage, Turn collects
tribute), i.e. a `Game`↔`Vassalage` cycle. Keeping the new pieces inside `Game`
matches convention and keeps the graph acyclic. No new context dependency edges
are required — the existing `GameLive -> Game`, `Game -> Worlds`, `Game -> Users`
edges cover all new components.

### New children of BrokenOaths.Game

- BrokenOaths.Game.Siege (module) [Story 906]: PvP city siege + capture. Composes
  Combat + CityDefense for the multi-turn HP grind and counter-attacks; the
  capture flow (zero HP breaks the city, moving a unit onto the tile occupies it);
  fallen-garrison execute/release with a small Honor delta; fires the last-free-city
  check. **Occupied state lives on the City schema** (an occupier field), not on the
  relationship — a city can be occupied without the owner being a vassal (a non-last
  city, criterion 7664), so occupation is a per-city fact distinct from Vassalage.
- BrokenOaths.Game.Vassalage (schema) [Story 907]: the player→player relationship
  record with day-one forward-looking fields (tribute_rate 0.25, oath_strain 0-100,
  hidden_agenda enum, contract_terms jsonb, status, Honor hooks).
- BrokenOaths.Game.Vassalization (module) [Story 907]: the subjugation pivot —
  last-free-city trigger, creates the Vassalage record, records the secret Hidden
  Agenda pick, notifies both players; deterministic when several last-cities fall
  in one tick.
- BrokenOaths.Game.Tribute (module) [Story 908]: per-turn gold tribute (vassal
  city-yield gold pre-upkeep × lord rate) with debt + gold log, plus call-to-arms
  levy issue/answer/refuse (Oath Strain + Honor on refusal); runs in the turn
  pipeline, scales to many relationships.
- BrokenOaths.Game.Levy (schema) [Story 908]: a call-to-arms pledge record (war,
  lord, vassal, pledged army share, status, war-duration binding).
- BrokenOaths.Game.GoldLog (schema) [Story 908]: a gold-transfer ledger entry both
  parties can see (world, turn, from/to player, amount, reason).

`Honor` is carried as a field on the existing `BrokenOaths.Game.Player` schema
(mutated by Siege on execute-garrison and by Tribute on levy refusal); the
`occupied` marker and the peacetime owner-runs-it rule extend the existing
`BrokenOaths.Game.City` schema — both are spec-time field additions, no new
component.

### New children of BrokenOathsWeb.GameLive

- BrokenOathsWeb.GameLive.OathPanel (liveview_component) [Story 907]: the
  Terms-of-Oath screen — secret Hidden Agenda pick on subjugation.
- BrokenOathsWeb.GameLive.VassalsPanel (liveview_component) [Stories 907, 908]: the
  lord's Vassals list + per-vassal tribute-rate control + gold log + call-to-arms
  issue; the vassal's "Sworn to X" indicator + rate + answer/refuse controls.

The board attack affordance and occupied rendering extend the existing
`GameLive.Play` and `GameLive.CityPanel` surfaces (spec-time additions).
