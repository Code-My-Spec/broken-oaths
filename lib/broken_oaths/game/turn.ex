defmodule BrokenOaths.Game.Turn do
  @moduledoc """
  Pure turn pipeline — `tick/1` resolves every queued move order
  simultaneously and advances the turn counter. No processes, no `Repo`
  calls: this is the functional core the `WorldServer` (the imperative
  shell) holds in memory and drives once per turn boundary.

  ## Canonical tick-state contract

  This is the shape `WorldServer` must hold and pass to `tick/1`; every
  other functional-core module (`Spawner`, `Visibility`) is written
  against the same shape.

      state :: %{
        world: %Worlds.World{},
        turn: non_neg_integer(),
        units: %{unit_id => %{
          id: unit_id,
          player_id: player_id,
          type: :lord | :settler,
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
        explored: %{player_id => MapSet.t(tile_id)}
      }

  `unit_id` and `player_id` are opaque keys (Ecto primary keys in
  production); `tile_id` is a `Worlds.Globe` mesh tile id.

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
  """

  alias BrokenOaths.Game.Visibility

  @type unit_id :: term()
  @type player_id :: term()
  @type tile_id :: non_neg_integer()

  @type unit :: %{
          id: unit_id(),
          player_id: player_id(),
          type: :lord | :settler,
          tile_id: tile_id(),
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          movement: non_neg_integer(),
          max_movement: non_neg_integer()
        }

  @type order :: %{kind: :move, path: [tile_id()], status: :pending | :interrupted}

  @type player :: %{id: player_id(), user_id: term(), region_id: term(), gold: non_neg_integer()}

  @type state :: %{
          world: BrokenOaths.Worlds.World.t(),
          turn: non_neg_integer(),
          units: %{unit_id() => unit()},
          orders: %{unit_id() => order()},
          players: %{player_id() => player()},
          explored: %{player_id() => MapSet.t(tile_id())}
        }

  @type event :: {:turn_advanced, non_neg_integer()}

  @doc """
  Advance the world by one turn: reset movement, resolve every pending
  move order simultaneously, refresh each player's explored set, and bump
  the turn counter.

  Returns `{new_state, events}`; `events` always includes
  `{:turn_advanced, new_turn}` for the caller to broadcast.
  """
  @spec tick(state()) :: {state(), [event()]}
  def tick(state) do
    new_turn = state.turn + 1

    new_state =
      state
      |> reset_movement()
      |> resolve_orders()
      |> refresh_explored()
      |> Map.put(:turn, new_turn)

    {new_state, [{:turn_advanced, new_turn}]}
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
      for {unit_id, %{kind: :move, status: :pending, path: path}} <- state.orders, path != [], into: %{} do
        unit = Map.fetch!(state.units, unit_id)
        {unit_id, %{tile_id: unit.tile_id, path: path, status: :pending, movement_left: unit.movement}}
      end

    positions = Map.new(state.units, fn {id, unit} -> {id, unit.tile_id} end)

    {movers, positions} = run_rounds(movers, positions)

    %{state | units: apply_positions(state.units, movers, positions), orders: apply_orders(state.orders, movers)}
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
    |> Enum.filter(fn {_id, m} -> m.status == :pending and m.path != [] and m.movement_left > 0 end)
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
        {:ok, mover} -> {id, %{unit | tile_id: Map.fetch!(positions, id), movement: mover.movement_left}}
        :error -> {id, unit}
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
