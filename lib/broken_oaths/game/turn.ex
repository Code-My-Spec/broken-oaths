defmodule BrokenOaths.Game.Turn do
  @moduledoc """
  Pure turn pipeline — `tick/1` resolves every queued move order
  simultaneously and advances the turn counter. No processes, no `Repo`
  calls: this is the functional core the `WorldServer` (the imperative
  shell) holds in memory and drives once per turn boundary.

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
          max_movement: non_neg_integer()
        }},
        orders: %{unit_id => %{
          kind: :move,
          path: [tile_id],
          status: :pending | :interrupted
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
          territory: [tile_id],
          worked_tiles: [tile_id],
          queue: [%{id: term(), type: :settler | :worker | :warrior,
                    banked: non_neg_integer(), cost: pos_integer()}]
        }},
        improvements: %{tile_id => %{
          tile_id: tile_id,
          kind: :farm | :mine | :road,
          progress: non_neg_integer(),
          status: :building | :complete,
          builder_unit_id: unit_id | nil
        }}
      }

  `unit_id`, `player_id`, and `city_id` are opaque keys (Ecto primary
  keys in production); `tile_id` is a `Worlds.Globe` mesh tile id.

  ## Movement resolution

  At the start of a tick every unit's `movement` resets to its
  `max_movement`. Orders with `status: :pending` then resolve in lockstep
  rounds: one step per round per still-active mover, movers processed in
  ascending unit id each round for determinism. A step is blocked when its
  destination is occupied at that instant — either by a unit that never
  moves this round or by a unit that claimed the tile earlier in the same
  round. A blocked mover halts for the rest of the tick: its order becomes
  `:interrupted` and its remaining path (including the blocked step) is
  preserved untouched. `:interrupted` orders are not retried until
  something re-queues them — that is outside this module. A path fully
  consumed within the tick is an arrival: the order is removed entirely.

  ## City loop phases

  After movement resolves, `tick/1` runs the city-loop phases in a
  fixed order, each a thin pass over `state.cities`/`state.improvements`
  delegating the real math to `Yields` and `Production`:

    1. improvement progress -- ticks `Improvement.duration/1` forward
       for any improvement whose declared builder is still standing on
       its tile.
    2. production accrual -- `Production.accrue/3` (flat base plus
       worked-tile production) into each city's current queue item.
    3. completions/spawn placement -- `Production.complete/3`; a
       completed item with nowhere to land simply waits. Successful
       spawns come back as `{:unit_spawned, spawn_event}` events --
       this module never allocates a real unit id itself.
    4. food accrual -- `Yields.accrue_food/3`.
    5. growth -- `Yields.grow/3`, at most once per city per tick.
    6. healing -- a unit that spent no movement this tick heals: 15 HP
       garrisoned on its own city's tile, 10 HP anywhere else in its
       owner's territory, 0 outside it.

  Cities are always processed in ascending id order within a phase, so
  contested outcomes (two cities eligible for the same growth tile, two
  production completions racing for a tile) resolve deterministically.
  """

  alias BrokenOaths.Game.Improvement
  alias BrokenOaths.Game.Production
  alias BrokenOaths.Game.Visibility
  alias BrokenOaths.Game.Yields

  @type unit_id :: term()
  @type player_id :: term()
  @type city_id :: term()
  @type tile_id :: non_neg_integer()

  @type unit :: %{
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
          tile_id: tile_id(),
          kind: Improvement.kind(),
          progress: non_neg_integer(),
          status: Improvement.status(),
          builder_unit_id: unit_id() | nil
        }

  @type state :: %{
          world: BrokenOaths.Worlds.World.t(),
          turn: non_neg_integer(),
          units: %{unit_id() => unit()},
          orders: %{unit_id() => order()},
          players: %{player_id() => player()},
          explored: %{player_id() => MapSet.t(tile_id())},
          cities: %{city_id() => city()},
          improvements: %{tile_id() => improvement()}
        }

  @type event ::
          {:turn_advanced, non_neg_integer()} | {:unit_spawned, Production.spawn_event()}

  @doc """
  Advance the world by one turn: reset movement, resolve every pending
  move order simultaneously, run the city-loop phases (see this
  module's "City loop phases" doc above), refresh each player's
  explored set, and bump the turn counter.

  Returns `{new_state, events}`; `events` always includes
  `{:turn_advanced, new_turn}`, plus one `{:unit_spawned, spawn_event}`
  per completed production item that found a landing tile this tick —
  `new_state.units` does NOT yet contain those units, since only the
  caller (`WorldServer`) can allocate a real, persisted unit id.
  """
  @spec tick(state()) :: {state(), [event()]}
  def tick(state) do
    new_turn = state.turn + 1

    state =
      state
      |> reset_movement()
      |> resolve_orders()
      |> advance_improvements()
      |> accrue_production()

    {state, spawn_events} = resolve_completions(state)

    new_state =
      state
      |> accrue_food()
      |> grow_cities()
      |> heal_units()
      |> refresh_explored()
      |> Map.put(:turn, new_turn)

    events = [{:turn_advanced, new_turn} | Enum.map(spawn_events, &{:unit_spawned, &1})]

    {new_state, events}
  end

  @doc """
  Immediate movement: spend `unit_id`'s remaining points on its pending
  order right now. Orders execute as they're issued — the turn boundary
  only recharges movement and continues whatever path remains. Same
  collision semantics as the tick: a step into an occupied tile
  interrupts the order in place.
  """
  @spec move_now(state(), term()) :: state()
  def move_now(state, unit_id) do
    case Map.get(state.orders, unit_id) do
      %{kind: :move, status: :pending, path: path} when path != [] ->
        unit = Map.fetch!(state.units, unit_id)

        movers = %{
          unit_id => %{
            tile_id: unit.tile_id,
            path: path,
            status: :pending,
            movement_left: unit.movement
          }
        }

        positions = Map.new(state.units, fn {id, u} -> {id, u.tile_id} end)
        {movers, positions} = run_rounds(movers, positions)

        %{
          state
          | units: apply_positions(state.units, movers, positions),
            orders: apply_orders(state.orders, movers)
        }
        |> refresh_explored()

      _ ->
        state
    end
  end

  # -------------------------------------------------------------------
  # Movement point reset
  # -------------------------------------------------------------------

  defp reset_movement(state) do
    units = Map.new(state.units, fn {id, unit} -> {id, %{unit | movement: unit.max_movement}} end)
    %{state | units: units}
  end

  # -------------------------------------------------------------------
  # Simultaneous move resolution
  # -------------------------------------------------------------------

  defp resolve_orders(state) do
    movers =
      for {unit_id, %{kind: :move, status: :pending, path: path}} <- state.orders,
          path != [],
          into: %{} do
        unit = Map.fetch!(state.units, unit_id)

        {unit_id,
         %{tile_id: unit.tile_id, path: path, status: :pending, movement_left: unit.movement}}
      end

    positions = Map.new(state.units, fn {id, unit} -> {id, unit.tile_id} end)

    {movers, positions} = run_rounds(movers, positions)

    %{
      state
      | units: apply_positions(state.units, movers, positions),
        orders: apply_orders(state.orders, movers)
    }
  end

  defp run_rounds(movers, positions) do
    case active_movers(movers) do
      [] ->
        {movers, positions}

      ids ->
        {movers, positions} = Enum.reduce(ids, {movers, positions}, &attempt_step/2)
        run_rounds(movers, positions)
    end
  end

  defp active_movers(movers) do
    movers
    |> Enum.filter(fn {_id, m} ->
      m.status == :pending and m.path != [] and m.movement_left > 0
    end)
    |> Enum.map(fn {id, _m} -> id end)
    |> Enum.sort()
  end

  defp attempt_step(unit_id, {movers, positions}) do
    mover = Map.fetch!(movers, unit_id)
    [target | rest] = mover.path

    if target in Map.values(positions) do
      {Map.put(movers, unit_id, %{mover | status: :interrupted}), positions}
    else
      moved = %{mover | tile_id: target, path: rest, movement_left: mover.movement_left - 1}
      {Map.put(movers, unit_id, moved), Map.put(positions, unit_id, target)}
    end
  end

  defp apply_positions(units, movers, positions) do
    Map.new(units, fn {id, unit} ->
      case Map.fetch(movers, id) do
        {:ok, mover} ->
          {id, %{unit | tile_id: Map.fetch!(positions, id), movement: mover.movement_left}}

        :error ->
          {id, unit}
      end
    end)
  end

  # Orders whose path emptied this tick (arrival) are dropped entirely.
  defp apply_orders(orders, movers) do
    orders
    |> Enum.map(fn {id, order} ->
      case Map.fetch(movers, id) do
        {:ok, mover} -> {id, %{order | path: mover.path, status: mover.status}}
        :error -> {id, order}
      end
    end)
    |> Enum.reject(fn {_id, order} -> order.path == [] end)
    |> Map.new()
  end

  # -------------------------------------------------------------------
  # Improvement progress
  # -------------------------------------------------------------------

  # Only an improvement whose declared builder is STILL standing on its
  # tile advances — "one unit per hex" means at most one candidate
  # builder can ever be present, so there's no concurrent-builder case
  # to arbitrate. Anyone else (owner or not — improvements aren't
  # owned) who later starts the same kind on this tile reattaches and
  # resumes from whatever `progress` was frozen at.
  defp advance_improvements(state) do
    improvements =
      Map.new(state.improvements, fn {tile_id, improvement} ->
        {tile_id, advance_improvement(improvement, state.units)}
      end)

    %{state | improvements: improvements}
  end

  defp advance_improvement(%{status: :complete} = improvement, _units), do: improvement
  defp advance_improvement(%{builder_unit_id: nil} = improvement, _units), do: improvement

  defp advance_improvement(improvement, units) do
    case Map.get(units, improvement.builder_unit_id) do
      %{tile_id: tile_id} when tile_id == improvement.tile_id ->
        finish_or_progress(improvement)

      _still_present ->
        %{improvement | builder_unit_id: nil}
    end
  end

  defp finish_or_progress(improvement) do
    progress = improvement.progress + 1
    duration = Improvement.duration(improvement.kind)

    if progress >= duration do
      %{improvement | progress: duration, status: :complete, builder_unit_id: nil}
    else
      %{improvement | progress: progress}
    end
  end

  # -------------------------------------------------------------------
  # Production: accrual, completion, spawn placement
  # -------------------------------------------------------------------

  defp accrue_production(state) do
    cities =
      Map.new(state.cities, fn {id, city} ->
        {id, Production.accrue(city, state.world, state.improvements)}
      end)

    %{state | cities: cities}
  end

  # Threads a running "occupied tiles" set through cities in ascending
  # id order, so a spawn from one city in this same tick correctly
  # blocks a landing tile for the next city's completion — before
  # either lands in `state.units`, which only the caller can update
  # (see `tick/1`'s doc on `{:unit_spawned, _}` events).
  defp resolve_completions(state) do
    occupied = Map.new(state.units, fn {_id, unit} -> {unit.tile_id, true} end)
    ids = state.cities |> Map.keys() |> Enum.sort()

    {cities, events, _occupied} =
      Enum.reduce(ids, {state.cities, [], occupied}, &resolve_city_completion(state.world, &1, &2))

    {%{state | cities: cities}, events}
  end

  defp resolve_city_completion(world, id, {cities, events, occupied}) do
    city = Map.fetch!(cities, id)
    {new_city, city_events} = Production.complete(city, occupied, world)
    newly_occupied = Map.new(city_events, fn event -> {event.tile_id, true} end)

    {Map.put(cities, id, new_city), events ++ city_events, Map.merge(occupied, newly_occupied)}
  end

  # -------------------------------------------------------------------
  # Food accrual and growth
  # -------------------------------------------------------------------

  defp accrue_food(state) do
    cities =
      Map.new(state.cities, fn {id, city} ->
        {id, Yields.accrue_food(city, state.world, state.improvements)}
      end)

    %{state | cities: cities}
  end

  # Each city grows against the CURRENT territory of every city
  # (including siblings already grown earlier in this same reduce), so
  # two cities eligible for the same tile in one tick resolve by
  # ascending city id — the same determinism rule the doc promises.
  defp grow_cities(state) do
    ids = state.cities |> Map.keys() |> Enum.sort()

    cities =
      Enum.reduce(ids, state.cities, fn id, cities ->
        city = Map.fetch!(cities, id)
        grown = Yields.grow(city, Map.values(cities), state.world)
        Map.put(cities, id, grown)
      end)

    %{state | cities: cities}
  end

  # -------------------------------------------------------------------
  # Healing
  # -------------------------------------------------------------------

  # "Unmoved" is read straight off this tick's movement ledger: a unit
  # that spent zero movement points still holds `movement == max_movement`
  # after `resolve_orders`, whether that's because it had no order or
  # because its order was blocked before its first step.
  defp heal_units(state) do
    units = Map.new(state.units, fn {id, unit} -> {id, heal(unit, state.cities)} end)
    %{state | units: units}
  end

  defp heal(%{hp: hp, max_hp: max_hp} = unit, _cities) when hp >= max_hp, do: unit

  defp heal(unit, cities) do
    if unit.movement == unit.max_movement do
      %{unit | hp: min(unit.max_hp, unit.hp + heal_rate(unit, cities))}
    else
      unit
    end
  end

  defp heal_rate(unit, cities) do
    owned = for {_id, city} <- cities, city.player_id == unit.player_id, do: city

    cond do
      Enum.any?(owned, &(&1.tile_id == unit.tile_id)) -> 15
      Enum.any?(owned, &(unit.tile_id in &1.territory)) -> 10
      true -> 0
    end
  end

  # -------------------------------------------------------------------
  # Exploration
  # -------------------------------------------------------------------

  defp refresh_explored(state) do
    explored =
      Map.new(state.players, fn {player_id, _player} ->
        units = for {_id, unit} <- state.units, unit.player_id == player_id, do: unit
        newly_visible = Visibility.visible_tiles(state.world, units)
        prior = Map.get(state.explored, player_id, MapSet.new())
        {player_id, MapSet.union(prior, newly_visible)}
      end)

    %{state | explored: explored}
  end
end
