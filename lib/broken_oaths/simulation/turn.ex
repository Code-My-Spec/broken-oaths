defmodule BrokenOaths.Simulation.Turn do
  @moduledoc """
  Pure turn pipeline — `tick/1` resolves every queued move order
  simultaneously and advances the turn counter. No processes, no `Repo`
  calls: this is the functional core the `WorldServer` (the imperative
  shell) holds in memory and drives once per turn boundary.

  `tick/1` itself is a thin SEQUENCE of each phase's own domain-model
  function — the pragdave decomposition's "Turn -> a pure pipeline that
  SEQUENCES each domain's own tick phase" (see
  `.code_my_spec/knowledge/genserver_decomposition.md`). Every phase's
  actual behavior lives on the domain model that owns it (or, for the
  handful genuinely cross-cutting with no single owner, on a
  `BrokenOaths.Simulation.Turn.*` submodule); this module wires the ORDER and
  threads state/events between them. See the "City loop phases" section
  below for exactly which module owns which phase, and the note on each
  phase's own function doc for the full behavior contract.

  ## Canonical tick-state contract

  This is the shape `WorldServer` must hold and pass to `tick/1`; every
  other functional-core module (`Spawner`, `Visibility`, `Yields`,
  `Production`) is written against the same shape.

      state :: %{
        world: %Worlds.World{},
        turn: non_neg_integer(),
        units: %{unit_id => %{
          id: unit_id,
          player_id: player_id,
          type: :lord | :settler | :warrior | :worker,
          tile_id: tile_id,
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          movement: non_neg_integer(),
          max_movement: non_neg_integer(),
          charges: non_neg_integer()
        }},
        orders: %{unit_id => %{
          kind: :move | :road_to,
          path: [tile_id],
          status: :pending | :interrupted,
          hp_at_issue: non_neg_integer() | nil
        }},
        players: %{player_id => %{
          id: player_id,
          user_id: term(),
          region_id: term(),
          gold: non_neg_integer()
        }},
        explored: %{player_id => MapSet.t(tile_id)},
        cities: %{city_id => %{
          id: city_id,
          player_id: player_id,
          tile_id: tile_id,
          name: String.t(),
          size: pos_integer(),
          food: non_neg_integer(),
          hp: non_neg_integer(),
          territory: [tile_id],
          worked_tiles: [tile_id],
          queue: [%{id: term(), type: :settler | :worker | :warrior,
                    banked: non_neg_integer(), cost: pos_integer()}]
        }},
        improvements: %{tile_id => %{
          tile_id: tile_id,
          kind: :farm | :mine | :road | :pasture,
          progress: non_neg_integer(),
          status: :building | :complete,
          builder_unit_id: unit_id | nil
        }},
        roads: %{tile_id => %{
          tile_id: tile_id,
          kind: :road,
          progress: non_neg_integer(),
          status: :building | :complete,
          builder_unit_id: unit_id | nil
        }},
        pending_heirs: %{player_id => non_neg_integer()},
        camps: %{camp_id => %{
          id: camp_id,
          tile_id: tile_id,
          hp: non_neg_integer(),
          spawn_counter: non_neg_integer(),
          destroyed_at: term() | nil
        }}
      }

  `charges` (story 882 playtest update, issue 1caa87e9) is read
  defensively via `Map.get(unit, :charges, 3)` everywhere it's read
  (now `BrokenOaths.Cities.Improvement`'s own advance phase) — most of
  this module's own pre-existing unit tests build a hand-written unit
  map with no `:charges` key at all, and a unit that predates the
  charges migration would likewise have none in a raw hand-built map,
  so the same "3, same as a freshly spawned worker" default the DB
  migration itself uses applies here too.

  `pending_heirs` (story 896) is read defensively via
  `Map.get(state, :pending_heirs, %{})` — a scheduled-heir arrival turn
  per player, written by `WorldServer`'s combat handler on a lord's
  death, resolved by `BrokenOaths.Simulation.Turn.HeirSuccession`'s own tick
  phase. It's the one field in this contract every other functional-core
  module (and most of this module's own tests, built before it
  existed) can safely omit; nothing breaks if it's absent.

  `camps` (story 892) is read the same defensive way, via
  `Map.get(state, :camps, %{})` — every barbarian camp on the board,
  written once at a player's first founding (`WorldServer`, not this
  module) and advanced every tick by `BrokenOaths.Combat.Camps`'s own
  spawn-loop phase. A unit belonging to a camp (a barbarian warrior)
  carries the camp's id as `camp_id` in its own map, read the same
  defensive way (`Map.get(unit, :camp_id)`) since ordinary player units
  never set it.

  `player_research` (story 902) is read the same defensive way, via
  `Map.get(state, :player_research, %{})` — one
  `BrokenOaths.Technology.Research.player_research()` map per player, created
  at join (`WorldServer`, not this module) and advanced every tick by
  `BrokenOaths.Technology.Research`'s own science-accrual phase (below). A
  player with no entry is treated as `BrokenOaths.Technology.Research.new/0`
  for that tick only — most of this module's own tests build a state
  map without this key.

  `roads` (QA issue 5656770d "Roads conflict with improvements") is
  read the same defensive way, via `Map.get(state, :roads, %{})` — most
  of this module's own unit tests predate the split and never set it. A
  Road is a movement/connectivity improvement, orthogonal to whatever
  yield improvement (Farm/Mine/Pasture) already occupies `improvements`
  at the same `tile_id` — the two are independent slots, each advanced
  by `BrokenOaths.Cities.Improvement`'s own advance phase exactly the
  same way (that module's own advance/pillage/charge logic is agnostic
  to which of the two maps an improvement happens to live in; only
  `BrokenOaths.Simulation.WorldServer` — the imperative shell — cares, since
  it's the one enforcing which slot a given `kind` belongs to and
  persisting each slot to its own DB row). See `BrokenOaths.Cities.Improvement`'s
  own moduledoc for the full rationale.

  `unit_id`, `player_id`, and `city_id` are opaque keys (Ecto primary
  keys in production); `tile_id` is a `Worlds.Globe` mesh tile id.

  ## Movement resolution

  `BrokenOaths.Simulation.Turn.Movement` (`reset_movement/1`, `resolve_orders/1`,
  `advance_fortify/1`) — see that module's own moduledoc for the full
  lockstep-round collision contract. At the start of EVERY tick every
  unit's `movement` resets to its `max_movement` unconditionally (the
  timer inversion, below); orders with `status: :pending` then resolve
  in lockstep rounds, one step per round per still-active mover,
  movers processed in ascending unit id each round for determinism.
  Right after, `advance_fortify/1` ramps the Fortify stance (story 920)
  of every unit that stayed put and didn't fight this tick.

  ## Timer inversion — fast tick vs. economy tick

  Movement used to recharge only every `recharge_turns` ticks (story
  924), which stranded a unit on an off-turn — a live bug. The timer
  inversion (prod-critical tick change) flips the throttle: movement,
  combat, barbarians, fortify, healing, and heir succession all run on
  the FAST layer (unthrottled, every tick — the 1-minute action
  cadence), while only the ECONOMY — improvement progress, production
  accrual/completions, science accrual, food accrual/growth — slows
  down, running once every `world.economy_turns` ticks (default 10 =
  10 minutes on a 60s tick). `economy? = rem(new_turn,
  economy_turns) == 0` is computed once per tick and threaded through
  every economy-gated phase below (`economy_turns` itself read
  defensively via `Map.get(state.world, :economy_turns, 10) || 10`, so
  an in-memory world built before this field existed still gets the
  default cadence rather than crashing). `recharge_turns` (story 924's
  own field) is retired — nothing reads it anymore; see `Worlds.World`'s
  own doc.

  On a tick where `economy?` is `false`, each economy phase below is
  skipped and its output is the SAME neutral shape a real run would
  produce on a turn with nothing to do: `Production.resolve_completions/1`'s
  own `occupied` map (`%{tile_id => true}`, the exact shape it itself
  starts from before folding in any completions) is rebuilt directly
  off `state.units`, so phase 3b/3c below still see a correct
  occupied-tile set to spawn camps/barbarians against even though
  phase 3 itself didn't run; `spawn_events`, `settled_this_tick`, and
  `city_completions` are simply empty, same as a real tick that
  happened to complete nothing. `WorldServer`'s own income/upkeep
  sweep (`Bank.apply_upkeep/2`, via `apply_bank/1`) is gated on the
  SAME `economy?` formula, recomputed there off `new_state.turn`/
  `new_state.world` after `tick/1` returns — see that module's own
  `apply_bank/1` doc.

  ## City loop phases

  After movement resolves, `tick/1` runs the city-loop phases in a
  fixed order, each delegating to the domain model that owns it (or, if
  genuinely cross-cutting with no single owner, a `Turn.*` submodule).
  ECONOMY-gated phases (only on an `economy?` tick) are marked below;
  everything else runs every tick regardless:

    1. [ECONOMY] improvement progress -- `BrokenOaths.Cities.Improvement.advance/1`.
    2. [ECONOMY] production accrual -- `BrokenOaths.Cities.Production.accrue_cities/1`,
       EXCEPT a pillaged city still serving its own production halt
       (story 895).
    3. [ECONOMY] completions/spawn placement -- `BrokenOaths.Cities.Production.
       resolve_completions/1`; a completed item with nowhere to land
       simply waits. Successful spawns come back as `{:unit_spawned,
       spawn_event}` events -- this module never allocates a real unit
       id itself.
    3b. camp spawn loop (story 892) -- `BrokenOaths.Combat.Camps.
       resolve_spawns/2`, threading the SAME "claimed this tick"
       occupied-tile set phase 3 built (or, on a non-economy tick, the
       neutral occupied set described above).
    3c. barbarian AI loop (story 893) -- `BrokenOaths.Simulation.Turn.
       BarbarianPhase.resolve/3` (cross-cutting: orchestrates
       `BarbarianAI`, `Combat`, `CityDefense`, and heir scheduling
       together, so it has no single owning domain model).
    3d. city regeneration (story 895) -- `BrokenOaths.Combat.CityDefense.
       regen_cities/2`, skipping every city phase 3c's own barbarian-AI
       assault struck THIS tick.
    3e. road-to walk-or-build (story 929) -- `BrokenOaths.Simulation.
       Turn.RoadBuilder.resolve/1` (cross-cutting: walks `Units.Unit`'s
       own worker and builds through `Cities.Improvement`, so it has
       no single owning domain model, the same status 3c/7 below
       already have). NEVER economy-gated -- a `:road_to` order's own
       walk should feel as responsive as an ordinary move order, even
       though the Road improvement it starts only actually progresses
       on an economy tick (phase 1 above). Runs after 3c so this same
       tick's own barbarian damage (if any) already counts toward its
       own "attacked mid-build cancels" check.
    4. [ECONOMY] food accrual -- `BrokenOaths.Cities.Yields.accrue_food_all/1`.
    5. [ECONOMY] growth -- `BrokenOaths.Cities.Yields.grow_cities/2`, at
       most once per city per tick, and never for a city that already
       paid a settler's population cost in phase 3 THIS SAME tick
       (issue 63300098).
    6. healing -- `BrokenOaths.Units.Unit.heal_all/1`: a unit that spent
       no movement this tick heals 15 HP garrisoned on its own city's
       tile, 10 HP anywhere else in its owner's territory, 0 outside it.
    7. heir succession -- `BrokenOaths.Simulation.Turn.HeirSuccession.resolve/2`
       (cross-cutting: touches `Player`/`Unit`/`City` at once with no
       single owning domain model). Any player whose lord died gets a
       fresh Lord at their capital this tick, plus a
       `{:lineage_continued, user_id, message}` event.
    8. [ECONOMY] science accrual (story 902) -- `BrokenOaths.Technology.Research.
       accrue_science/1`; a tech that reaches its cost completes
       automatically and fires `{:tech_completed, user_id, tech}`.

  Cities are always processed in ascending id order within a phase, so
  contested outcomes (two cities eligible for the same growth tile, two
  production completions racing for a tile) resolve deterministically.
  """

  alias BrokenOaths.Combat.Camps
  alias BrokenOaths.Combat.CityDefense
  alias BrokenOaths.Cities.Improvement
  alias BrokenOaths.Cities.Production
  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Simulation.Turn.BarbarianPhase
  alias BrokenOaths.Simulation.Turn.HeirSuccession
  alias BrokenOaths.Simulation.Turn.Movement
  alias BrokenOaths.Simulation.Turn.RoadBuilder
  alias BrokenOaths.Units.Unit
  alias BrokenOaths.Vision.Visibility
  alias BrokenOaths.Cities.Yields

  @type unit_id :: term()
  @type player_id :: term()
  @type city_id :: term()
  @type tile_id :: non_neg_integer()

  @type unit :: %{
          optional(:charges) => non_neg_integer(),
          id: unit_id(),
          player_id: player_id(),
          type: :lord | :settler | :warrior | :worker,
          tile_id: tile_id(),
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          movement: non_neg_integer(),
          max_movement: non_neg_integer()
        }

  @type order :: %{kind: :move, path: [tile_id()], status: :pending | :interrupted}

  @type player :: %{id: player_id(), user_id: term(), region_id: term(), gold: non_neg_integer()}

  @type city :: Production.city()
  @type improvement :: %{
          optional(:duration) => pos_integer() | nil,
          tile_id: tile_id(),
          kind: Improvement.kind(),
          progress: non_neg_integer(),
          status: Improvement.status(),
          builder_unit_id: unit_id() | nil
        }

  @type camp_id :: term()
  @type camp :: Camps.camp()

  @type state :: %{
          world: BrokenOaths.Worlds.World.t(),
          turn: non_neg_integer(),
          units: %{unit_id() => unit()},
          orders: %{unit_id() => order()},
          players: %{player_id() => player()},
          explored: %{player_id() => MapSet.t(tile_id())},
          cities: %{city_id() => city()},
          improvements: %{tile_id() => improvement()},
          camps: %{camp_id() => camp()}
        }

  @type event ::
          {:turn_advanced, non_neg_integer()}
          | {:unit_spawned, Production.spawn_event()}
          | {:lineage_continued, term(), String.t()}
          # Playtest issue 6 — the "build complete" toast: one per queue
          # item (unit or building) that finished THIS tick. See
          # `Production.resolve_completions/1`'s own doc for why this
          # rides a separate list from `{:unit_spawned, _}` above.
          | {:city_completed, term(), String.t(), Production.buildable()}
          # Story 929 — a `:road_to` order's own worker arrived at a
          # gap tile with no road row there yet at all; see
          # `RoadBuilder`'s own "Pure core, impure shell" moduledoc
          # section for why this can't just insert the row itself.
          # Purely internal plumbing: `WorldServer.run_tick/1`'s own
          # `materialize_road_starts/2` consumes and drops every one of
          # these before `events` is ever broadcast to a client.
          | RoadBuilder.event()

  @doc """
  Advance the world by one turn: reset movement, resolve every pending
  move order simultaneously, run the city-loop phases (see this
  module's "City loop phases" doc above), refresh each player's
  explored set, and bump the turn counter.

  Returns `{new_state, events}`; `events` always includes
  `{:turn_advanced, new_turn}`, plus one `{:unit_spawned, spawn_event}`
  per completed production item that found a landing tile this tick —
  `new_state.units` does NOT yet contain those units, since only the
  caller (`WorldServer`) can allocate a real, persisted unit id — and
  one `{:city_completed, user_id, city_name, type}` per queue item
  that actually finished this tick, unit (needs a landing tile, same
  gate `{:unit_spawned, _}` above already sits behind) or Granary
  (needs none — see `Production.resolve_completions/1`'s own doc)
  alike (playtest issue 6's "build complete" toast).
  """
  @spec tick(state()) :: {state(), [event()]}
  def tick(state) do
    new_turn = state.turn + 1
    economy? = economy_tick?(state, new_turn)

    # Snapshot each unit's tile before the movement phase so Unit.heal_all/2 can
    # tell who actually moved this tick — healing is gated on "didn't move",
    # decoupled from the fast/economy tick split (timer inversion).
    tiles_before = Map.new(state.units, fn {id, u} -> {id, u.tile_id} end)

    state =
      state
      |> Movement.reset_movement()
      |> Movement.resolve_orders()
      |> Movement.advance_fortify()

    state =
      if economy?, do: state |> Improvement.advance() |> Production.accrue_cities(), else: state

    {state, spawn_events, occupied, settled_this_tick, city_completions} =
      if economy? do
        Production.resolve_completions(state)
      else
        {state, [], occupied_tiles(state), MapSet.new(), []}
      end

    {state, camp_events, occupied} = Camps.resolve_spawns(state, occupied)
    {state, attacked_cities} = BarbarianPhase.resolve(state, occupied, new_turn)
    {state, heir_events} = HeirSuccession.resolve(state, new_turn)
    {state, tech_events} = if economy?, do: Research.accrue_science(state), else: {state, []}

    # Story 929 — every `:road_to` order's own one-segment-per-tick
    # walk-or-build step (never economy-gated, see `RoadBuilder`'s own
    # moduledoc), placed AFTER `BarbarianPhase` so this same tick's own
    # barbarian damage already shows in `state.units` for its own
    # "attacked mid-build cancels" check. `road_events` (a brand new
    # road's own `{:road_start_needed, ...}`, when one is needed) rides
    # the SAME "pure tick emits, the imperative shell materializes"
    # split `spawn_events`/`camp_events` above already use — see
    # `RoadBuilder`'s own moduledoc, "Pure core, impure shell".
    {state, road_events} = RoadBuilder.resolve(state)

    new_state =
      state
      |> Improvement.clear_orphaned_builders()
      |> CityDefense.regen_cities(attacked_cities)
      |> maybe_grow(economy?, settled_this_tick)
      |> Unit.heal_all(tiles_before)
      |> Visibility.refresh_explored()
      |> Map.put(:turn, new_turn)

    events =
      [
        {:turn_advanced, new_turn}
        | Enum.map(spawn_events ++ camp_events, &{:unit_spawned, &1})
      ] ++
        heir_events ++
        tech_events ++
        road_events ++
        Enum.map(city_completions, &{:city_completed, &1.user_id, &1.city_name, &1.type})

    {new_state, events}
  end

  # Timer inversion — whether THIS tick is an economy tick, per the formula
  # `WorldServer`'s own `apply_bank/1` must recompute identically after
  # `tick/1` returns (see that module's doc). `economy_turns` is read the
  # same defensive way every other story-924-and-later field is (`Map.get`
  # with a fallback) so an in-memory world built before the column existed
  # still gets the default cadence rather than crashing.
  defp economy_tick?(state, new_turn), do: rem(new_turn, economy_turns(state)) == 0

  defp economy_turns(state), do: Map.get(state.world, :economy_turns, 10) || 10

  # The neutral `occupied` phase 3 (`Production.resolve_completions/1`)
  # would otherwise build on a non-economy tick — the SAME `%{tile_id =>
  # true}` shape that function itself starts from before folding in any
  # completions THIS tick, so phase 3b/3c below still see a correct
  # occupied-tile set even though phase 3 didn't run to build one.
  defp occupied_tiles(state), do: Map.new(state.units, fn {_id, unit} -> {unit.tile_id, true} end)

  defp maybe_grow(state, false, _settled_this_tick), do: state

  defp maybe_grow(state, true, settled_this_tick) do
    state
    |> Yields.accrue_food_all()
    |> Yields.grow_cities(settled_this_tick)
  end

  @doc """
  Immediate movement: spend `unit_id`'s remaining points on its pending
  order right now. Orders execute as they're issued — the turn boundary
  only recharges movement and continues whatever path remains. Same
  collision semantics as the tick: a step into an occupied tile
  interrupts the order in place. Delegates entirely to
  `BrokenOaths.Simulation.Turn.Movement.move_now/2` — see that module's own
  doc for the full behavior.
  """
  @spec move_now(state(), term()) :: state()
  def move_now(state, unit_id), do: Movement.move_now(state, unit_id)
end
