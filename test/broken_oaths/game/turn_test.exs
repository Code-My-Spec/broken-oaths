defmodule BrokenOaths.Game.TurnTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.Research
  alias BrokenOaths.Game.Turn
  alias BrokenOaths.Game.Visibility
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @frequency 8
  @seed 424_242

  defp world, do: %World{seed: @seed, frequency: @frequency}

  defp unit(id, opts) do
    max_movement = Keyword.get(opts, :max_movement, 2)
    max_hp = Keyword.get(opts, :max_hp, 10)

    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      type: Keyword.get(opts, :type, :settler),
      tile_id: Keyword.fetch!(opts, :tile),
      hp: Keyword.get(opts, :hp, max_hp),
      max_hp: max_hp,
      movement: Keyword.get(opts, :movement, max_movement),
      max_movement: max_movement
    }
  end

  defp base_state(units, orders \\ %{}) do
    player_ids = units |> Map.values() |> Enum.map(& &1.player_id) |> Enum.uniq()
    players = Map.new(player_ids, &{&1, %{id: &1, user_id: &1, region_id: 0, gold: 50}})

    %{
      world: world(),
      turn: 0,
      units: units,
      orders: orders,
      players: players,
      explored: %{},
      cities: %{},
      improvements: %{}
    }
  end

  defp city(id, opts) do
    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      tile_id: Keyword.fetch!(opts, :tile),
      name: Keyword.get(opts, :name, "City #{id}"),
      size: Keyword.get(opts, :size, 1),
      food: Keyword.get(opts, :food, 0),
      # Story 895: `CityDefense.regen/1` (wired into `Turn.regen_cities/2`)
      # requires city HP — `Game.City`'s own schema defaults a freshly
      # founded city to `CityDefense.max_hp/0` (100), so plain test-built
      # city maps mirror that same default here.
      hp: Keyword.get(opts, :hp, 100),
      territory: Keyword.get(opts, :territory, [Keyword.fetch!(opts, :tile)]),
      worked_tiles: Keyword.get(opts, :worked_tiles, []),
      queue: Keyword.get(opts, :queue, [])
    }
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

      orders = %{
        1 => %{kind: :move, path: [50], status: :pending},
        2 => %{kind: :move, path: [50], status: :pending}
      }

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

      state = %{
        state
        | players: %{1 => %{id: 1, user_id: 1, region_id: 0, gold: 50}},
          explored: %{}
      }

      {new_state, _events} = Turn.tick(state)

      assert new_state.explored[1] == MapSet.new()
    end
  end

  describe "tick/1 production and spawn placement" do
    test "a completed item spawns on the city's own tile when free, as a spawn event" do
      c = city(1, tile: 1, queue: [%{id: 10, type: :warrior, banked: 35, cost: 40}])
      state = %{base_state(%{}) | cities: %{1 => c}}

      {new_state, events} = Turn.tick(state)

      assert new_state.cities[1].queue == []
      assert {:unit_spawned, %{player_id: 1, type: :warrior, tile_id: 1}} in events
      # Turn never allocates a real unit id itself — only the caller can.
      assert new_state.units == %{}
    end

    test "an occupied city tile places the unit on a free adjacent tile instead" do
      c = city(1, tile: 1, queue: [%{id: 10, type: :warrior, banked: 40, cost: 40}])
      blocker = unit(99, tile: 1, player_id: 2, type: :lord)
      state = %{base_state(%{99 => blocker}) | cities: %{1 => c}}

      {new_state, events} = Turn.tick(state)

      assert [{:unit_spawned, %{tile_id: landed}}] =
               Enum.filter(events, &match?({:unit_spawned, _}, &1))

      refute landed == 1
      assert landed in Regions.adjacent_tiles(world(), 1)
      assert new_state.cities[1].queue == []
    end

    test "a fully blocked city keeps its item queued without losing banked production" do
      land_neighbors =
        world()
        |> Regions.adjacent_tiles(1)
        |> Enum.filter(&(Regions.tile_class(world(), &1) == :land))

      blockers =
        [1 | land_neighbors]
        |> Enum.with_index(100)
        |> Map.new(fn {tile, id} -> {id, unit(id, tile: tile, player_id: 2, type: :lord)} end)

      c = city(1, tile: 1, queue: [%{id: 10, type: :warrior, banked: 40, cost: 40}])
      state = %{base_state(blockers) | cities: %{1 => c}}

      {new_state, events} = Turn.tick(state)

      refute Enum.any?(events, &match?({:unit_spawned, _}, &1))
      assert [%{banked: banked}] = new_state.cities[1].queue
      assert banked >= 45
    end
  end

  describe "tick/1 improvement progress" do
    test "advances progress when the declared builder is still on the tile" do
      worker = unit(1, tile: 100, type: :worker)

      improvement = %{
        tile_id: 100,
        kind: :farm,
        progress: 1,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].progress == 2
      assert new_state.improvements[100].status == :building
    end

    test "completes once progress reaches the kind's duration, clearing the builder" do
      worker = unit(1, tile: 100, type: :worker)

      improvement = %{
        tile_id: 100,
        kind: :road,
        progress: 1,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :complete
      assert new_state.improvements[100].progress == 2
      assert new_state.improvements[100].builder_unit_id == nil
    end

    # Story 902, criterion 7628 — `improvement.duration`, when present,
    # overrides `Improvement.duration(kind)` (`WorldServer.
    # persist_start_improvement!/3` is what actually resolves it from
    # research; here we only need to prove `Turn` HONORS it).
    test "a stored :duration overrides the kind's base duration" do
      worker = unit(1, tile: 100, type: :worker)

      improvement = %{
        tile_id: 100,
        kind: :mine,
        progress: 2,
        status: :building,
        duration: 3,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :complete
      assert new_state.improvements[100].progress == 3
      assert new_state.improvements[100].builder_unit_id == nil
    end

    test "no :duration key falls back to the kind's base — the mine still needs 5" do
      worker = unit(1, tile: 100, type: :worker)

      improvement = %{
        tile_id: 100,
        kind: :mine,
        progress: 3,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :building
      assert new_state.improvements[100].progress == 4
    end

    test "a builder that moves away this tick freezes progress and clears the builder" do
      [target | _] = Regions.adjacent_tiles(world(), 100)
      worker = unit(1, tile: 100, type: :worker, max_movement: 2)
      order = %{kind: :move, path: [target], status: :pending}

      improvement = %{
        tile_id: 100,
        kind: :mine,
        progress: 2,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}, %{1 => order}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].progress == 2
      assert new_state.improvements[100].builder_unit_id == nil
    end

    test "no builder present leaves progress untouched" do
      improvement = %{
        tile_id: 100,
        kind: :mine,
        progress: 3,
        status: :building,
        builder_unit_id: nil
      }

      state = %{base_state(%{}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100] == improvement
    end

    test "a complete improvement never advances further" do
      improvement = %{
        tile_id: 100,
        kind: :farm,
        progress: 3,
        status: :complete,
        builder_unit_id: nil
      }

      state = %{base_state(%{}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100] == improvement
    end
  end

  describe "tick/1 food accrual and growth" do
    test "food accrues and a city at threshold grows, claiming a new tile" do
      c = city(1, tile: 1, food: 18, territory: [1])
      state = %{base_state(%{}) | cities: %{1 => c}}

      {new_state, _events} = Turn.tick(state)

      grown = new_state.cities[1]
      assert grown.size == 2
      assert length(grown.territory) == 2
    end

    test "growth respects a rival city's prior claim on the same tiles" do
      neighbors = Regions.adjacent_tiles(world(), 1)
      rival = city(2, tile: 600, territory: neighbors, player_id: 2)
      c = city(1, tile: 1, food: 25, territory: [1])
      state = %{base_state(%{}) | cities: %{1 => c, 2 => rival}}

      {new_state, _events} = Turn.tick(state)

      grown = new_state.cities[1]
      assert grown.size == 2
      assert grown.territory == [1]
    end
  end

  describe "tick/1 healing" do
    test "unmoved-at-home heals 10, garrisoned-on-the-city-tile heals 15, abroad heals 0" do
      neighbors = Regions.adjacent_tiles(world(), 1)
      [home_tile | _] = neighbors

      abroad_tile =
        neighbors
        |> Enum.flat_map(&Regions.adjacent_tiles(world(), &1))
        |> Enum.uniq()
        |> Enum.reject(&(&1 == 1 or &1 in neighbors))
        |> List.first()

      c = city(1, tile: 1, territory: [1 | neighbors])

      home = unit(1, tile: home_tile, hp: 50, max_hp: 100, type: :warrior, max_movement: 1)
      garrison = unit(2, tile: 1, hp: 50, max_hp: 100, type: :warrior, max_movement: 1)
      abroad = unit(3, tile: abroad_tile, hp: 50, max_hp: 100, type: :warrior, max_movement: 1)

      state = %{base_state(%{1 => home, 2 => garrison, 3 => abroad}) | cities: %{1 => c}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].hp == 60
      assert new_state.units[2].hp == 65
      assert new_state.units[3].hp == 50
    end

    test "a unit that moved this tick does not heal, even in home territory" do
      neighbors = Regions.adjacent_tiles(world(), 1)
      [target | _] = neighbors
      c = city(1, tile: 1, territory: [1 | neighbors])

      mover = unit(1, tile: 1, hp: 50, max_hp: 100, max_movement: 1)
      order = %{kind: :move, path: [target], status: :pending}
      state = %{base_state(%{1 => mover}, %{1 => order}) | cities: %{1 => c}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].hp == 50
    end

    test "a unit already at full HP is left alone" do
      c = city(1, tile: 1)
      full_hp = unit(1, tile: 1, hp: 100, max_hp: 100)
      state = %{base_state(%{1 => full_hp}) | cities: %{1 => c}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].hp == 100
    end
  end

  describe "tick/1 science accrual (story 902)" do
    defp research_state(city, player_research) do
      %{base_state(%{}) | cities: %{1 => city}}
      |> Map.put(:players, %{1 => %{id: 1, user_id: 1, region_id: 0, gold: 50}})
      |> Map.put(:player_research, %{1 => player_research})
    end

    test "banks 2 science per population point toward current_research" do
      c = city(1, tile: 1, size: 3)
      state = research_state(c, %{Research.new() | current_research: :pottery})

      {new_state, _events} = Turn.tick(state)

      # size 3 * 2 science/pop = 6 banked toward pottery.
      assert Research.banked(new_state.player_research[1], :pottery) == 6
    end

    test "a player with no current_research banks nothing" do
      c = city(1, tile: 1, size: 4)
      state = research_state(c, Research.new())

      {new_state, events} = Turn.tick(state)

      assert new_state.player_research[1] == Research.new()
      refute Enum.any?(events, &match?({:tech_completed, _, _}, &1))
    end

    test "auto-completes a tech the instant its cost is banked, and clears current_research" do
      c = city(1, tile: 1, size: 4)
      pr = %{Research.new() | current_research: :pottery} |> Research.accrue(42)
      state = research_state(c, pr)

      {new_state, events} = Turn.tick(state)

      completed = new_state.player_research[1]
      assert :pottery in completed.completed_techs
      assert completed.current_research == nil
      assert {:tech_completed, 1, :pottery} in events
    end

    test "a tech below cost keeps banking without completing" do
      c = city(1, tile: 1, size: 1)
      pr = %{Research.new() | current_research: :bronze_working}
      state = research_state(c, pr)

      {new_state, events} = Turn.tick(state)

      not_yet = new_state.player_research[1]
      assert Research.banked(not_yet, :bronze_working) == 2
      assert not_yet.current_research == :bronze_working
      refute Enum.any?(events, &match?({:tech_completed, _, _}, &1))
    end

    test "each player accrues independently against their own cities' population" do
      city_a = city(1, tile: 1, player_id: 1, size: 2)
      city_b = city(2, tile: 10, player_id: 2, size: 4)
      state = %{base_state(%{}) | cities: %{1 => city_a, 2 => city_b}}

      state =
        state
        |> Map.put(:players, %{
          1 => %{id: 1, user_id: 1, region_id: 0, gold: 50},
          2 => %{id: 2, user_id: 2, region_id: 1, gold: 50}
        })
        |> Map.put(:player_research, %{
          1 => %{Research.new() | current_research: :mining},
          2 => %{Research.new() | current_research: :mining}
        })

      {new_state, _events} = Turn.tick(state)

      assert Research.banked(new_state.player_research[1], :mining) == 4
      assert Research.banked(new_state.player_research[2], :mining) == 8
    end

    test "a player missing from player_research entirely is treated as a fresh, unstarted player" do
      c = city(1, tile: 1, size: 2)
      state = %{base_state(%{}) | cities: %{1 => c}}
      state = Map.put(state, :players, %{1 => %{id: 1, user_id: 1, region_id: 0, gold: 50}})

      {new_state, _events} = Turn.tick(state)

      assert new_state.player_research[1] == Research.new()
    end
  end
end
