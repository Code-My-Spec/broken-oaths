# LiveView / OTP Game Architecture for Broken Oaths

Research compiled 2026-07-13 for the first multiplayer-gameplay milestone. This
sits on top of the existing rendering doctrine in `board_architecture.md` — the
two rules there (JS owns the camera only; everything must be LiveView-testable)
are load-bearing constraints for every decision below, not incidental.

Current state we are building on: worlds are seed-generated (terrain is a pure
function of `seed` + `frequency`, never persisted), there is **one LiveView per
viewer**, and camera/rendering is solved. What is missing is authoritative,
shared, mutable game state — players, units, cities, ownership, turns/ticks —
and its persistence.

The central architectural fact that makes this easy: **the seed-derived world is
already server-authoritative and stateless-per-viewer.** Adding gameplay means
adding exactly one shared mutable thing per world — a process — and teaching each
per-viewer LiveView to read from and write to it. Nothing about the renderer
changes.

---

## 1. Authoritative game state: one process per world

**Decision: a `WorldServer` GenServer per active world, started on demand,
registered by world id, supervised by a `DynamicSupervisor`.** This is the
near-universal pattern in every Elixir multiplayer writeup surveyed
([AppSignal Go](https://blog.appsignal.com/2019/08/13/elixir-alchemy-multiplayer-go-with-registry-pubsub-and-dynamic-supervisors.html),
[Charles Desneuf event-sourced game](https://blog.charlesdesneuf.com/articles/phoenix-liveview-event-sourced-game-architecture/),
[Fly.io distributed turn-based](https://fly.io/blog/building-a-distributed-turn-based-game-system-in-elixir/),
[dkarter's LiveView games talk](https://speakerdeck.com/dkarter/building-multiplayer-games-with-phoenix-liveview)).

Per-world (not per-match, not per-player) is the right grain for a persistent
Civ-like world: the world *is* the match, and all units/cities/players inside it
share one consistent state that must be serialized through a single process.

Concrete shape:

- **Registry with via-tuples** to name processes by world id instead of atoms.
  Atoms are never GC'd, so naming thousands of worlds with atoms would leak;
  the Registry maps the string/integer id to a pid:
  `{:via, Registry, {BrokenOaths.WorldRegistry, world_id}}`. The Registry must
  start **before** the DynamicSupervisor in the supervision tree
  ([AppSignal](https://blog.appsignal.com/2019/08/13/elixir-alchemy-multiplayer-go-with-registry-pubsub-and-dynamic-supervisors.html)).
- **`DynamicSupervisor` (`:one_for_one`)** starts a `WorldServer` on demand the
  first time a viewer opens a world, with **`restart: :transient`** so a clean
  shutdown (empty world) stays down but a crash restarts.
- **Functional core / imperative shell.** The GenServer holds state and
  serializes access; all *rules* live in pure functions (`WorldServer` calls
  `Game.dispatch(state, command) -> {events | error}`). Desneuf and dkarter both
  stress this split: it keeps the process thin and makes the rules unit- and
  property-testable with zero OTP or renderer in the loop. This is the exact
  analogue of the existing `Generator`/`Terrain` pure modules.

### LiveView ↔ WorldServer handoff

On `mount/3`, the viewer's LiveView:

1. Looks up (or lazily starts) the `WorldServer` for the world id via the
   DynamicSupervisor + Registry.
2. Subscribes to the world's PubSub topic (`"world:#{id}"`).
3. Pulls a **snapshot** of current state (`GenServer.call`) to render the first
   frame — the same "fetch current state on mount, then live-update" pattern
   Desneuf uses (views fetch all past events on mount, then subscribe).

The LiveView keeps a *projection* of world state in its assigns (units, cities,
selected tile). It never holds the authoritative copy — that is the WorldServer's
job. On a player action it `cast`s/`call`s a command to the WorldServer; the
WorldServer validates, mutates, and broadcasts the resulting diff. This keeps
the board doctrine intact: every game-meaningful action is a server round-trip
against server-authoritative state.

### PubSub fan-out and backpressure (10–100 viewers/world)

Broadcast **diffs, not whole-world snapshots**, on `"world:#{id}"`. At 10–100
viewers per world this is comfortably within Phoenix.PubSub's design envelope —
a broadcast sends one message to the pg2 group and each node fans out to local
subscribers ([PubSub internals](https://elixirforum.com/t/phoenix-pubsub-subscriptions-performance/20644)).
Watch two things:

- **Unbounded mailbox growth if a client can't keep up** with publish rate
  ([scaling thread](https://elixirforum.com/t/how-to-scale-phoenix-pubsub-event-publishing/66201)).
  Mitigate by broadcasting *coalesced* diffs on a tick boundary rather than one
  message per micro-mutation, and keeping payloads small (ids + deltas, never
  re-pushing terrain — it's seed-derived and already client-side).
- Keep game-state diffs **out of LiveView's own change-tracking diff** when they
  target the hook-owned canvas. Per the existing perf invariants, unit/overlay
  geometry destined for the canvas should ride `push_event` into the
  `phx-update="ignore"` layer, exactly like the current tile-window payloads —
  *but* anything that must be assertable in a test needs a server-rendered
  surface (see §6). Plan a server-rendered unit/city list (sidebar, or an SR-only
  layer) so tests have a DOM handle even when the pretty version is canvas-drawn.

---

## 2. Tick / turn systems

**Decision for the first milestone: a `Process.send_after` self-tick inside the
`WorldServer`, driving a slow world clock; gameplay actions are
event-driven/immediate on top of it.** The canonical Elixir recurring-work
pattern is `Process.send_after(self(), :tick, interval)` in `init/1`, then
reschedule inside `handle_info(:tick, state)`
([Elixir School](https://elixirschool.com/blog/til-send-after),
[GenServer docs](https://hexdocs.pm/elixir/GenServer.html)). Store the timer ref
in state so it can be cancelled on pause.

Guidance from the survey:

- **Real-time ticks** = `send_after` loop (above). **Sequential turns** need no
  timer — advance state on the "end turn" command. **Simultaneous turns** =
  collect all players' orders, resolve on a tick or when the last player commits.
  A Civ-like world usually wants a *hybrid*: turn-based player actions with a
  slow background world tick (growth/production) so an idle world still evolves.
- **Catch-up:** don't assume ticks fire on time. Compute elapsed wall-clock
  (`System.monotonic_time`) each tick and advance state by the elapsed number of
  logical ticks, so a descheduled or reloaded process doesn't silently drop
  game time.
- **Pause empty worlds.** dkarter runs a dedicated `GameGarbageCollector`
  GenServer on a ~2-minute interval that shuts down games with zero connected
  players; AppSignal uses a ~10-minute inactivity `:transient` timeout. For us,
  couple this to Presence (§4): when the last viewer leaves, **stop ticking and
  persist**, then let the process idle-timeout and terminate. It restarts from
  the persisted snapshot when someone returns. This is the single most important
  cost control — thousands of dormant worlds should cost zero CPU.

---

## 3. Persistence: snapshot + delta, because terrain is free

**Decision: persist a periodic snapshot of the *mutable delta* over the seed —
never the terrain — plus an idle/last-viewer-leaves flush. Event sourcing is
deferred, not adopted, for the first milestone.**

Reasoning:

- Terrain is a pure function of `(seed, frequency)`. It is already never
  persisted and must stay that way — persisting it would be redundant and huge.
  Persist only what the seed can't reproduce: **players, unit positions/state,
  city placements, tile ownership, resources, current turn/tick number.**
- **Snapshot vs event sourcing.** Full event sourcing (Desneuf, Commanded)
  gives replayable history and audit, but Desneuf's own tradeoff note is the
  warning for us: his events live *in-process only*, so "we cannot get back to
  where the game was in case of a crash… Everything is lost"
  ([architecture post](https://blog.charlesdesneuf.com/articles/phoenix-liveview-event-sourced-game-architecture/)).
  Event sourcing is worth it only once you *durably* store the log and need
  history/rewind. For a first gameplay milestone, a **snapshot** of the delta
  (Ecto → Postgres, a `jsonb` or typed columns keyed by world id) is far less
  machinery and recovers fully. When streams later grow, the standard move is
  snapshot-plus-replay-tail ([Event Sourcing with Elixir](https://allanmacgregor.com/posts/event-sourcing-with-elixir)) —
  but keep the *functional core emitting events* now (§1) so upgrading to a
  durable event log later is additive, not a rewrite.
- **Write-behind, not write-through.** The WorldServer mutates in memory (hot
  path stays fast) and persists asynchronously: on each world tick, on the
  last-viewer-leaves transition, and on process shutdown. The common Elixir
  pattern is exactly this — entity lives in memory, persists a snapshot when it
  goes idle ([EventBus/write-behind discussion](https://github.com/slashdotdash/awesome-elixir-cqrs)).
- **ETS as hot cache** is *not* needed yet: the WorldServer's own process heap
  *is* the hot cache (one authoritative reader/writer). Reach for ETS only if
  read concurrency outgrows the single process (e.g. many viewers doing heavy
  independent reads) — then publish a read-optimized copy into an ETS table the
  LiveViews read directly. Note it for later; don't build it now.
- **Crash recovery:** `:transient` restart + "load latest snapshot in `init/1`"
  gives automatic recovery to the last persisted tick. Accept losing at most one
  tick's worth of mutations — cheap and simple. Terrain rehydrates for free from
  the seed.

---

## 4. Presence + per-player visibility (fog of war)

**Decision: `Phoenix.Presence` for who's-viewing; fog of war computed
server-side and filtered per LiveView, because each viewer already is its own
process.**

- **Presence** tracks connected viewers per world topic and drives the
  pause/GC logic in §2. dkarter enriches Presence with a **custom `fetch`
  callback** that pulls extra per-player data from the GameServer — useful for a
  player list / "who's online in this world" sidebar.
- **Fog of war — filter per subscriber, don't broadcast per subscriber.** The
  architecture already hands us the clean solution: one LiveView process per
  viewer. So the WorldServer broadcasts the *full* diff once (cheap, single
  PubSub message, fastlane-friendly), and **each LiveView filters it against its
  own player's visibility** in `handle_info` before touching assigns/pushing to
  canvas. This keeps fan-out O(1) in messages while visibility stays
  server-authoritative (the client never receives tiles it shouldn't — filtering
  happens in the LiveView process on the server, not in JS). The alternative —
  the WorldServer computing and unicasting a bespoke payload per player — is only
  worth it if hidden information is *large or sensitive enough* that sending it
  to the viewer's own server process is unacceptable; for a first milestone,
  LiveView-side filtering is simpler and fully testable. Keep the visibility
  function pure (`Visibility.visible?(world_state, player_id, tile_id)`) so it's
  property-testable and reusable by both the filter and the renderer.

---

## 5. Optimistic UI vs server round-trip

**Decision: server round-trip is the default; reserve client-side prediction
for camera-like feedback only — this is the board doctrine, restated.**

The doctrine says hooks own the camera and pixels, never game state. So:

- **Game actions** (move, build, attack, end-turn) are LiveView events → server
  validation → broadcast diff. Over a WebSocket on a nearby node this is a few
  tens of ms; Fly.io's model is explicitly "connect the viewer's *LiveView* to a
  nearby node, let the authoritative GameServer live wherever"
  ([Fly.io](https://fly.io/blog/building-a-distributed-turn-based-game-system-in-elixir/)),
  which keeps the round-trip snappy without giving the client authority.
- **Instant-feel without client authority:** allowed optimism is *presentational*
  and camera-owned — hover highlights, a "pending" ghost/selection ring drawn by
  the hook while the server confirms, movement-range previews computed from
  already-pushed data. These never mutate authoritative state; when the server
  diff arrives it is the source of truth and reconciles the ghost. This is
  exactly how the existing selection ring works (`push_event "globe3d:selected"`)
  — extend that channel for pending-action affordances, not for state.
- **Latency budget:** target < ~100 ms action→confirm on-continent. If a future
  action ever needs sub-frame response (rare for a turn/tick strategy game),
  that's the only case to consider client-side prediction — and it would need a
  reconciliation protocol, so avoid until proven necessary.

---

## 6. Testing multiplayer

**Decision: LiveViewTest with multiple concurrent connected views on one shared
WorldServer for integration; StreamData property tests on the pure game core for
rules. This is mandatory infrastructure, not optional.**

- **Concurrent views, one world.** `live/2` mounts a connected, stateful
  LiveView process ([LiveViewTest docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html)).
  Mount two (or N) connected views against the same world id — they share the
  same WorldServer via the Registry — then assert that an action driven in view A
  (`render_click`) becomes visible in view B after the PubSub broadcast. This is
  the core multiplayer test and it needs **no browser**. Extend the existing
  `globe_helpers.ex` blessed entry points (`click_tile`, `select_tile_at`) with
  multiplayer helpers (`start_viewers/2`, `assert_sees/3`).
  - Consequence for §1: because LiveViewTest selectors only see
    **server-rendered** DOM, at least one assertable surface for every gameplay
    fact (a unit exists here, this city is mine, it's my turn) must be
    server-rendered — a sidebar list, or an SR-only layer — even when the pretty
    rendering is canvas. dkarter calls this "gray box" testing: fast, aware of
    internal state, far less brittle than pixel/UI testing.
- **Property-based rules testing** with
  [StreamData](https://github.com/whatyouhide/stream_data): generate random
  legal command sequences against the pure `Game.dispatch/2` core and assert
  invariants (unit count conserved except on death, no two cities on one tile,
  ownership is total-and-disjoint, turn order well-formed). Shrinking finds the
  minimal failing sequence; the ExUnit `--seed` makes failures deterministically
  reproducible ([StreamData](https://elixir-lang.org/blog/2017/10/31/stream-data-property-based-testing-and-data-generation-for-elixir/)).
- **Deterministic simulation.** Because the core is pure and terrain is
  seed-derived, a whole game is reproducible from `(world seed, rng seed, command
  list)`. Lean into this: a sim test that runs thousands of ticks headless and
  asserts the world never enters an illegal state. This is the highest-leverage
  bug-finder for a rules engine and is only possible because state is
  server-side and pure — another reason to hold the functional-core line.

---

## 7. Scaling shape: what to assume now vs keep clean for later

**Decision: assume single-node now; keep the Registry indirection and pure core
so multi-node is a swap, not a rewrite.**

- **Safe single-node assumptions today:** one BEAM node; a plain `Registry` +
  `DynamicSupervisor`; the WorldServer's heap as the only cache;
  `persistent_term`/module attributes for read-only per-node data (meshes,
  palettes, budgets — already how `Globe`/`Texture` warm at boot). No
  clustering, no Horde, no distributed anything.
- **What to keep clean for the multi-node future** (do *not* build now):
  - **Address worlds only through the Registry via-tuple.** Never hold a raw pid
    across a call boundary. Swapping `Registry`→`Horde.Registry` and
    `DynamicSupervisor`→`Horde.DynamicSupervisor` is then a near drop-in, which
    is exactly the Fly.io distributed-turn-based design (Horde distributed
    registry + libcluster + WireGuard, single authoritative GameServer per game,
    *not* replicated) ([Fly.io](https://fly.io/blog/building-a-distributed-turn-based-game-system-in-elixir/)).
  - **Keep the game core pure and serializable** so a world can be handed off /
    migrated between nodes via its snapshot.
  - **Keep PubSub topics per-world** (`"world:#{id}"`) — already cluster-safe;
    Phoenix.PubSub fans out across nodes unchanged.
  - Per-node caches must be *derivable* (from seed/snapshot), never
    authoritative, so a second node can rebuild them independently.
- **Don't prematurely adopt:** Horde, libcluster, Redis PubSub adapter,
  ETS/read-replicas, event sourcing. Each is a documented later step with a
  clear trigger (multi-region latency; read concurrency; durable history); none
  is justified by the first milestone and each adds real operational complexity
  the surveyed single-node projects deliberately avoid.

---

## Ranked architecture decisions for the first gameplay milestone

Ordered by build sequence and dependency (earlier items unblock later ones):

1. **`WorldServer` GenServer per world**, functional core (`Game.dispatch/2`
   pure) + thin OTP shell. *The foundation; everything else attaches here.*
2. **`Registry` (via-tuples) + `DynamicSupervisor` (`:one_for_one`,
   `:transient`)**, lazy-start on first viewer. Registry before supervisor in the
   tree. *Addressing + lifecycle.*
3. **LiveView ↔ WorldServer wiring:** `mount` looks up/starts the world,
   subscribes to `"world:#{id}"`, pulls a snapshot; actions are commands to the
   server; server broadcasts coalesced diffs. LiveView holds a projection, never
   authority. *Makes state shared and live.*
4. **Snapshot persistence of the delta over the seed** (Ecto/Postgres),
   write-behind on tick + last-viewer-leaves + shutdown; rehydrate in `init/1`.
   Terrain never persisted. *Durability without event-sourcing machinery.*
5. **World tick** via `Process.send_after` with wall-clock catch-up; **pause +
   persist when Presence hits zero**, idle-timeout the process. *Time + cost
   control.*
6. **`Phoenix.Presence`** per world (who's-viewing, drives §5's pause/GC), custom
   `fetch` for the player list.
7. **Fog of war as a pure `Visibility` function, filtered per LiveView** on
   broadcast receipt (not per-subscriber broadcast). *Server-authoritative,
   O(1) fan-out.*
8. **Server-rendered assertable surface for every gameplay fact** (units/cities
   list) so LiveViewTest can see it, even where the pretty render is canvas via
   `push_event`. *Pays off doctrine rule 2.*
9. **Test harness:** multi-view LiveViewTest helpers in `globe_helpers.ex` +
   StreamData property tests + a deterministic headless sim over the pure core.
10. **Optimistic feel = camera-owned only** (pending ghosts/highlights via
    `push_event`), reconciled by the authoritative diff. No client game authority.
11. **Single-node now; multi-node clean:** address only via Registry, keep core
    pure/serializable, per-world topics, derivable per-node caches. Horde/cluster
    deferred behind a clear trigger.

## Sources

- [AppSignal — Multiplayer Go with Registry, PubSub, DynamicSupervisors](https://blog.appsignal.com/2019/08/13/elixir-alchemy-multiplayer-go-with-registry-pubsub-and-dynamic-supervisors.html)
- [Charles Desneuf — Event-sourced game: Architecture](https://blog.charlesdesneuf.com/articles/phoenix-liveview-event-sourced-game-architecture/) · [Game Server](https://blog.charlesdesneuf.com/articles/phoenix-liveview-event-sourced-game-game-server/) · [Building views from events](https://blog.charlesdesneuf.com/articles/phoenix-liveview-event-sourced-game-building-views-states-and-reacting-to-changes/)
- [Fly.io — Building a Distributed Turn-Based Game System in Elixir](https://fly.io/blog/building-a-distributed-turn-based-game-system-in-elixir/)
- [dkarter — Building Multiplayer Games with Phoenix LiveView (Speaker Deck)](https://speakerdeck.com/dkarter/building-multiplayer-games-with-phoenix-liveview)
- [Phoenix.LiveViewTest docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html)
- [StreamData — repo](https://github.com/whatyouhide/stream_data) · [Elixir blog intro](https://elixir-lang.org/blog/2017/10/31/stream-data-property-based-testing-and-data-generation-for-elixir/)
- [Process.send_after tick pattern — Elixir School](https://elixirschool.com/blog/til-send-after) · [GenServer docs](https://hexdocs.pm/elixir/GenServer.html)
- [Phoenix.PubSub subscription performance](https://elixirforum.com/t/phoenix-pubsub-subscriptions-performance/20644) · [scaling event publishing](https://elixirforum.com/t/how-to-scale-phoenix-pubsub-event-publishing/66201)
- [Event Sourcing with Elixir — Allan MacGregor](https://allanmacgregor.com/posts/event-sourcing-with-elixir) · [awesome-elixir-cqrs](https://github.com/slashdotdash/awesome-elixir-cqrs)
