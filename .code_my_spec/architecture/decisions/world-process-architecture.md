# One GenServer per world with in-process turn tick

## Status
Accepted

## Context
The game is a persistent multiplayer world with a 60-second automatic
turn cycle (story: Automatic Turn Processing). Gameplay state is shared
and mutable across players, so it needs a single serialization point per
world; turns must fire on schedule whether or not anyone is connected
(with a cost story for dormant worlds).

## Options Considered
- **Oban / background job framework** — durable scheduling, but jobs are
  the wrong shape for a hot in-memory world: every tick would reload
  state, and intra-turn ordering guarantees come free in a process.
- **Per-world GenServer** — the standard Elixir game pattern
  (functional core / imperative shell): one process per world serializes
  all mutations, `Process.send_after` self-loop drives the tick,
  Registry via-tuples + DynamicSupervisor for addressing/supervision.

## Decision
One `WorldServer` GenServer per world, addressed via Registry, started
lazily under a DynamicSupervisor (`:transient`). The 60s turn tick is a
`Process.send_after` self-loop with wall-clock catch-up. LiveViews hold
only a projection: subscribe to `"world:#{id}"` PubSub, send commands to
the server, receive coalesced diffs. Fog-of-war filtering happens
per-LiveView against a pure visibility function, so hidden tiles never
reach a client. When presence drops to zero the world pauses, persists,
and idles out. No job framework for MVP; the pure game core keeps a
deterministic headless-simulation test path.

## Consequences
- Single-node assumption for MVP; multi-node later means swapping
  Registry for Horde — kept clean by addressing only via the Registry
  and keeping the core pure/serializable.
- Turn logic must live in pure functions (`World.tick(state) :: state`)
  so it is property-testable without processes.
- Multi-view LiveViewTest against one shared WorldServer is the
  required integration surface (action in view A observable in view B).
- Research basis: `.code_my_spec/knowledge/liveview_game_architecture.md`.
