defmodule BrokenOaths.Game.ProductionTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.Production
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  # Same fixture pair as turn_test.exs/spawner_test.exs/yields_test.exs.
  # Tile 7 is flat plains (1 food / 1 production) at this seed —
  # verified by scanning every land tile — which is what gives the
  # accrual tests a worked tile with nonzero production to observe.
  @frequency 8
  @seed 424_242
  @plains_tile 7

  defp world, do: %World{seed: @seed, frequency: @frequency}

  defp city(overrides) do
    Map.merge(
      %{player_id: 1, tile_id: 1, size: 1, territory: [1], worked_tiles: [], queue: []},
      Map.new(overrides)
    )
  end

  describe "catalog/0 and cost/1" do
    test "Settler 100, Worker 60, Warrior 40 — no Monument" do
      assert Production.catalog() == %{settler: 100, worker: 60, warrior: 40}
      assert Production.cost(:settler) == 100
      assert Production.cost(:worker) == 60
      assert Production.cost(:warrior) == 40
    end
  end

  describe "unit_stats/1" do
    test "matches the 100-point HP scale for every unit type" do
      assert Production.unit_stats(:lord) == %{hp: 150, movement: 2}
      assert Production.unit_stats(:settler) == %{hp: 50, movement: 2}
      assert Production.unit_stats(:warrior) == %{hp: 100, movement: 1}
      assert Production.unit_stats(:worker) == %{hp: 10, movement: 2}
    end
  end

  describe "new_item/1" do
    test "starts unbanked at the catalog cost" do
      assert Production.new_item(:warrior) == %{type: :warrior, banked: 0, cost: 40}
      assert Production.new_item(:settler) == %{type: :settler, banked: 0, cost: 100}
    end
  end

  describe "can_queue?/2" do
    test "a size-1 city cannot queue a Settler" do
      assert Production.can_queue?(city(size: 1), :settler) == {:error, :size_one}
    end

    test "a size-2+ city can queue a Settler" do
      assert Production.can_queue?(city(size: 2), :settler) == :ok
    end

    test "Worker and Warrior are always queueable" do
      assert Production.can_queue?(city(size: 1), :worker) == :ok
      assert Production.can_queue?(city(size: 1), :warrior) == :ok
    end
  end

  describe "accrue/3" do
    test "a no-op on an empty queue" do
      c = city(queue: [])
      assert Production.accrue(c, world(), %{}) == c
    end

    test "flat base alone with no worked tiles" do
      c = city(queue: [Production.new_item(:warrior)])
      accrued = Production.accrue(c, world(), %{})
      assert [%{banked: 5}] = accrued.queue
    end

    test "worked-tile production adds on top of the flat base" do
      c = city(worked_tiles: [@plains_tile], queue: [Production.new_item(:warrior)])
      accrued = Production.accrue(c, world(), %{})
      # Plains flat is 1 food / 1 production; flat base is 5.
      assert [%{banked: 6}] = accrued.queue
    end

    test "only the current (head) item banks — the rest of the queue is untouched" do
      c = city(queue: [Production.new_item(:warrior), Production.new_item(:worker)])
      accrued = Production.accrue(c, world(), %{})
      assert [%{type: :warrior, banked: 5}, %{type: :worker, banked: 0}] = accrued.queue
    end
  end

  describe "complete/3" do
    test "an item below cost does not complete" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :warrior, banked: 39, cost: 40}])
      assert Production.complete(c, %{}, world()) == {c, []}
    end

    test "an item at cost with a free city tile completes and spawns there" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :warrior, banked: 40, cost: 40}])
      {new_city, events} = Production.complete(c, %{}, world())

      assert new_city.queue == []
      assert events == [%{player_id: 1, type: :warrior, tile_id: 1}]
    end

    test "a completed item lands on a free adjacent tile when the city tile is occupied" do
      [neighbor | _] = Regions.adjacent_tiles(world(), 1) |> Enum.filter(&(Regions.tile_class(world(), &1) == :land))
      c = city(tile_id: 1, queue: [%{id: 1, type: :warrior, banked: 40, cost: 40}])
      occupied = %{1 => true}

      {_new_city, events} = Production.complete(c, occupied, world())
      assert [%{tile_id: landed}] = events
      assert landed == neighbor or landed in Regions.adjacent_tiles(world(), 1)
      refute landed == 1
    end

    test "nothing lost when every landing tile is occupied — the item just waits" do
      neighbors = Regions.adjacent_tiles(world(), 1) |> Enum.filter(&(Regions.tile_class(world(), &1) == :land))
      occupied = Map.new([1 | neighbors], &{&1, true})
      item = %{id: 1, type: :warrior, banked: 47, cost: 40}
      c = city(tile_id: 1, queue: [item])

      assert Production.complete(c, occupied, world()) == {c, []}
    end

    test "overflow carries into the next queued item" do
      c =
        city(
          tile_id: 1,
          queue: [%{id: 1, type: :warrior, banked: 47, cost: 40}, %{id: 2, type: :worker, banked: 0, cost: 60}]
        )

      {new_city, _events} = Production.complete(c, %{}, world())
      assert [%{id: 2, banked: 7}] = new_city.queue
    end

    test "a big overflow can cascade through more than one completion" do
      c =
        city(
          tile_id: 1,
          queue: [
            %{id: 1, type: :warrior, banked: 85, cost: 40},
            %{id: 2, type: :warrior, banked: 0, cost: 40}
          ]
        )

      {new_city, events} = Production.complete(c, %{}, world())
      assert new_city.queue == []
      assert length(events) == 2
    end

    test "a settler completion costs one population and un-works one tile" do
      c =
        city(
          tile_id: 1,
          size: 2,
          worked_tiles: [@plains_tile],
          queue: [%{id: 1, type: :settler, banked: 100, cost: 100}]
        )

      {new_city, events} = Production.complete(c, %{}, world())
      assert new_city.size == 1
      assert new_city.worked_tiles == []
      assert [%{type: :settler}] = events
    end

    test "a size-1 city's settler item waits, exactly like a blocked landing tile" do
      c = city(tile_id: 1, size: 1, queue: [%{id: 1, type: :settler, banked: 100, cost: 100}])
      assert Production.complete(c, %{}, world()) == {c, []}
    end

    test "territory is never touched by a settler's population cost" do
      c =
        city(
          tile_id: 1,
          size: 2,
          territory: [1, @plains_tile],
          worked_tiles: [@plains_tile],
          queue: [%{id: 1, type: :settler, banked: 100, cost: 100}]
        )

      {new_city, _events} = Production.complete(c, %{}, world())
      assert new_city.territory == [1, @plains_tile]
    end
  end

  describe "validate_founding/3" do
    test "refuses ocean/mountain tiles" do
      non_land = Enum.find(0..641, &(Regions.tile_class(world(), &1) != :land))
      assert Production.validate_founding(world(), [], non_land) == {:error, :invalid_terrain}
    end

    test "an empty world has no spacing constraint" do
      assert Production.validate_founding(world(), [], 1) == :ok
    end

    test "refuses founding within 3 hexes of an existing city" do
      target = land_ring(1, 3) |> List.first()
      existing = [city(tile_id: 1)]
      assert Production.validate_founding(world(), existing, target) == {:error, :too_close}
    end

    test "allows founding exactly 4 hexes from an existing city" do
      target = land_ring(1, 4) |> List.first()
      existing = [city(tile_id: 1)]
      assert Production.validate_founding(world(), existing, target) == :ok
    end
  end

  describe "founding_territory/2" do
    test "is the tile plus every mesh-adjacent neighbor, unconditionally" do
      territory = Production.founding_territory(world(), 50)
      neighbors = Regions.adjacent_tiles(world(), 50)

      assert MapSet.size(territory) == length(neighbors) + 1
      assert MapSet.member?(territory, 50)
      assert Enum.all?(neighbors, &MapSet.member?(territory, &1))
    end
  end

  # Land-only BFS ring, exactly like the spex's own "N hexes away"
  # helpers (see e.g. criterion 7462) — used here to build concrete
  # too-close/far-enough founding targets without hardcoding tile ids.
  defp land_ring(start, depth) do
    land? = fn t -> Regions.tile_class(world(), t) == :land end

    {frontier, _seen} =
      Enum.reduce(1..depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
        next =
          frontier
          |> Enum.flat_map(&Regions.adjacent_tiles(world(), &1))
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(seen, &1))
          |> Enum.filter(land?)

        {next, MapSet.union(seen, MapSet.new(next))}
      end)

    frontier
  end
end
