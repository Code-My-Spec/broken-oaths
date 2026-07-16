defmodule BrokenOaths.Game.CampsTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.Camps
  alias BrokenOaths.Game.Spawner
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @frequency 8
  @seed 424_242

  defp world, do: %World{seed: @seed, frequency: @frequency}

  defp home_region_and_city_tile do
    {:ok, %{region_id: region_id, lord_tile: lord_tile}} = Spawner.spawn_player(world(), [])
    region_tiles = world() |> Regions.partition() |> Map.fetch!(:regions) |> Map.fetch!(region_id)
    {MapSet.new(region_tiles), lord_tile}
  end

  describe "place_wilderness/6" do
    test "returns 5-8 tiles total: 1-2 inside the region, 4-6 outside it" do
      {home, city_tile} = home_region_and_city_tile()

      tiles =
        Camps.place_wilderness(world(), city_tile, home, MapSet.new(), MapSet.new(), {@seed, city_tile})

      near = Enum.filter(tiles, &MapSet.member?(home, &1))
      far = Enum.reject(tiles, &MapSet.member?(home, &1))

      assert length(tiles) in 5..8
      assert length(near) in 1..2
      assert length(far) in 4..6
      assert length(tiles) == length(Enum.uniq(tiles))
    end

    test "far tiles sit 8-15 hexes out over raw mesh adjacency" do
      {home, city_tile} = home_region_and_city_tile()

      tiles =
        Camps.place_wilderness(world(), city_tile, home, MapSet.new(), MapSet.new(), {@seed, city_tile})

      far = Enum.reject(tiles, &MapSet.member?(home, &1))

      within_7 = ring(city_tile, 7)
      within_15 = ring(city_tile, 15)

      for tile <- far do
        refute MapSet.member?(within_7, tile)
        assert MapSet.member?(within_15, tile)
      end
    end

    test "never places a camp on the founding city's own tile" do
      {home, city_tile} = home_region_and_city_tile()

      tiles =
        Camps.place_wilderness(world(), city_tile, home, MapSet.new(), MapSet.new(), {@seed, city_tile})

      refute city_tile in tiles
    end

    test "excludes tiles already explored from the far pool" do
      {home, city_tile} = home_region_and_city_tile()
      seed = {@seed, city_tile}

      first = Camps.place_wilderness(world(), city_tile, home, MapSet.new(), MapSet.new(), seed)
      first_far = Enum.reject(first, &MapSet.member?(home, &1))
      explored = MapSet.new(first_far)

      retried = Camps.place_wilderness(world(), city_tile, home, explored, MapSet.new(), seed)
      retried_far = Enum.reject(retried, &MapSet.member?(home, &1))

      assert Enum.all?(retried_far, &(&1 not in explored))
    end

    test "excludes occupied tiles from every pool" do
      {home, city_tile} = home_region_and_city_tile()
      occupied = home |> Enum.take(50) |> MapSet.new()

      tiles =
        Camps.place_wilderness(world(), city_tile, home, MapSet.new(), occupied, {@seed, city_tile})

      assert Enum.all?(tiles, &(&1 not in occupied))
    end

    test "is deterministic for the same seed" do
      {home, city_tile} = home_region_and_city_tile()
      seed = {@seed, city_tile}

      a = Camps.place_wilderness(world(), city_tile, home, MapSet.new(), MapSet.new(), seed)
      b = Camps.place_wilderness(world(), city_tile, home, MapSet.new(), MapSet.new(), seed)

      assert a == b
    end

    test "different seeds can yield different placements" do
      {home, city_tile} = home_region_and_city_tile()

      a = Camps.place_wilderness(world(), city_tile, home, MapSet.new(), MapSet.new(), {@seed, city_tile})
      b = Camps.place_wilderness(world(), city_tile, home, MapSet.new(), MapSet.new(), {@seed, :other})

      refute a == b
    end
  end

  describe "advance/2 and spawned/1" do
    defp camp(overrides) do
      Map.merge(%{id: 1, tile_id: 100, hp: 100, spawn_counter: 0, destroyed_at: nil}, overrides)
    end

    test "not ready before the 3-turn cadence" do
      {c1, ready1?} = Camps.advance(camp(%{}), 0)
      refute ready1?
      assert c1.spawn_counter == 1

      {c2, ready2?} = Camps.advance(c1, 0)
      refute ready2?
      assert c2.spawn_counter == 2
    end

    test "ready exactly on the 3rd tick, below cap" do
      {advanced, ready?} = Camps.advance(camp(%{spawn_counter: 2}), 0)
      assert ready?
      assert advanced.spawn_counter == 3
    end

    test "not ready at cadence when already at the 2-warrior cap" do
      {_advanced, ready?} = Camps.advance(camp(%{spawn_counter: 2}), 2)
      refute ready?
    end

    test "a destroyed camp is never ready and is left untouched" do
      camp = camp(%{spawn_counter: 2, destroyed_at: ~N[2026-01-01 00:00:00]})
      {advanced, ready?} = Camps.advance(camp, 0)
      refute ready?
      assert advanced == camp
    end

    test "spawned/1 resets the counter to zero" do
      assert Camps.spawned(camp(%{spawn_counter: 5})).spawn_counter == 0
    end
  end

  defp ring(start, depth) do
    Enum.reduce(1..depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
      next =
        frontier
        |> Enum.flat_map(&Regions.adjacent_tiles(world(), &1))
        |> Enum.uniq()
        |> Enum.reject(&MapSet.member?(seen, &1))

      {next, MapSet.union(seen, MapSet.new(next))}
    end)
    |> elem(1)
  end
end
