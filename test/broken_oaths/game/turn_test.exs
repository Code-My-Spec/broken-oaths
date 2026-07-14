defmodule BrokenOaths.Game.TurnTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.Turn
  alias BrokenOaths.Game.Visibility
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @frequency 8
  @seed 424242

  defp world, do: %World{seed: @seed, frequency: @frequency}

  defp unit(id, opts) do
    max_movement = Keyword.get(opts, :max_movement, 2)

    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      type: Keyword.get(opts, :type, :settler),
      tile_id: Keyword.fetch!(opts, :tile),
      hp: 10,
      max_hp: 10,
      movement: Keyword.get(opts, :movement, max_movement),
      max_movement: max_movement
    }
  end

  defp base_state(units, orders \\ %{}) do
    player_ids = units |> Map.values() |> Enum.map(& &1.player_id) |> Enum.uniq()
    players = Map.new(player_ids, &{&1, %{id: &1, user_id: &1, region_id: 0, gold: 50}})

    %{world: world(), turn: 0, units: units, orders: orders, players: players, explored: %{}}
  end

  describe "tick/1 turn counter" do
    test "advances the turn and returns a turn_advanced event" do
      {new_state, events} = Turn.tick(base_state(%{}))

      assert new_state.turn == 1
      assert {:turn_advanced, 1} in events
    end

    test "advances by one from any starting turn" do
      state = %{base_state(%{}) | turn: 41}
      {new_state, events} = Turn.tick(state)

      assert new_state.turn == 42
      assert {:turn_advanced, 42} in events
    end
  end

  describe "tick/1 movement" do
    test "resets movement to max_movement before consuming the path" do
      # movement is 0 going in (spent last tick); max_movement is 2, and a
      # 2-hex path should still fully resolve this tick.
      u = unit(1, tile: 5, movement: 0, max_movement: 2)
      order = %{kind: :move, path: [10, 11], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 11
      refute Map.has_key?(new_state.orders, 1)
    end

    test "a unit advances up to its movement rate; a longer path stays pending" do
      u = unit(1, tile: 5, max_movement: 2)
      order = %{kind: :move, path: [10, 11, 12], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 11
      assert new_state.units[1].movement == 0
      assert new_state.orders[1] == %{kind: :move, path: [12], status: :pending}
    end

    test "arrival (path fully consumed) removes the order" do
      u = unit(1, tile: 5, max_movement: 3)
      order = %{kind: :move, path: [10, 11], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 11
      assert new_state.units[1].movement == 1
      refute Map.has_key?(new_state.orders, 1)
    end

    test "a unit with no order does not move and keeps full movement" do
      u = unit(1, tile: 5, max_movement: 2)
      state = base_state(%{1 => u})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.units[1].movement == 2
    end

    test "a path whose first step is the unit's own current tile is blocked" do
      u = unit(1, tile: 5, max_movement: 1)
      order = %{kind: :move, path: [5], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.orders[1].status == :interrupted
    end
  end

  describe "tick/1 simultaneous conflict resolution" do
    test "two units converging on the same tile resolve to exactly one occupant, lowest id wins" do
      u1 = unit(1, tile: 1, max_movement: 1)
      u2 = unit(2, tile: 2, max_movement: 1)
      order1 = %{kind: :move, path: [50], status: :pending}
      order2 = %{kind: :move, path: [50], status: :pending}
      state = base_state(%{1 => u1, 2 => u2}, %{1 => order1, 2 => order2})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 50
      refute Map.has_key?(new_state.orders, 1)

      assert new_state.units[2].tile_id == 2
      assert new_state.orders[2] == %{kind: :move, path: [50], status: :interrupted}
    end

    test "the outcome is deterministic across repeated resolution of the same state" do
      u1 = unit(1, tile: 1, max_movement: 1)
      u2 = unit(2, tile: 2, max_movement: 1)
      orders = %{1 => %{kind: :move, path: [50], status: :pending}, 2 => %{kind: :move, path: [50], status: :pending}}
      state = base_state(%{1 => u1, 2 => u2}, orders)

      {first, _} = Turn.tick(state)
      {second, _} = Turn.tick(state)

      assert first.units == second.units
      assert first.orders == second.orders
    end
  end

  describe "tick/1 path interruption" do
    test "a stationary unit with no order blocks an incoming step" do
      mover = unit(1, tile: 5, max_movement: 1)
      blocker = unit(2, tile: 20, max_movement: 1)
      order = %{kind: :move, path: [20], status: :pending}
      state = base_state(%{1 => mover, 2 => blocker}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.orders[1] == %{kind: :move, path: [20], status: :interrupted}
      assert new_state.units[2].tile_id == 20
    end

    test "a path blocked mid-journey halts the unit and preserves the full remaining path" do
      mover = unit(1, tile: 5, max_movement: 3)
      blocker = unit(2, tile: 20, max_movement: 0)
      order = %{kind: :move, path: [10, 20, 30], status: :pending}
      state = base_state(%{1 => mover, 2 => blocker}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 10
      assert new_state.orders[1] == %{kind: :move, path: [20, 30], status: :interrupted}
    end

    test "an already-interrupted order is never retried this tick" do
      mover = unit(1, tile: 5, max_movement: 2)
      order = %{kind: :move, path: [20], status: :interrupted}
      state = base_state(%{1 => mover}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.orders[1] == order
    end
  end

  describe "tick/1 exploration" do
    test "explored grows to cover the unit's post-move vision" do
      mover = unit(1, tile: 0, max_movement: 1, type: :lord)
      [target | _] = Regions.adjacent_tiles(world(), 0)
      order = %{kind: :move, path: [target], status: :pending}
      state = base_state(%{1 => mover}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      expected = Visibility.visible_tiles(world(), [%{type: :lord, tile_id: target}])
      assert new_state.explored[1] == expected
    end

    test "explored accumulates across ticks rather than resetting" do
      far_tile = 300
      mover = unit(1, tile: 0, max_movement: 0, type: :settler)
      state = %{base_state(%{1 => mover}) | explored: %{1 => MapSet.new([far_tile])}}

      {new_state, _events} = Turn.tick(state)

      assert far_tile in new_state.explored[1]
    end

    test "a player with no units has an empty, unchanged explored set" do
      state = base_state(%{}, %{})
      state = %{state | players: %{1 => %{id: 1, user_id: 1, region_id: 0, gold: 50}}, explored: %{}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.explored[1] == MapSet.new()
    end
  end
end
