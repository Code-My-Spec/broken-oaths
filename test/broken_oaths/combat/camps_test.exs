defmodule BrokenOaths.Combat.CampsTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Combat.Camps
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
    # Ranges narrowed 5..8/4..6 -> 5..7/4..5 (v0.2.1 playtest balance
    # pass, issue 04931763): one fewer far camp on average, easing
    # peak simultaneous wilderness pressure. See `Camps`'s own doc.
    test "returns 5-7 tiles total: 1-2 inside the region, 4-5 outside it" do
      {home, city_tile} = home_region_and_city_tile()

      tiles =
        Camps.place_wilderness(world(), city_tile, home, MapSet.new(), MapSet.new(), {@seed, city_tile})

      near = Enum.filter(tiles, &MapSet.member?(home, &1))
      far = Enum.reject(tiles, &MapSet.member?(home, &1))

      assert length(tiles) in 5..7
      assert length(near) in 1..2
      assert length(far) in 4..5
      assert length(tiles) == length(Enum.uniq(tiles))
    end

    # Regression for the v0.2.1 playtest report "camps too close
    # together" (issue 04931763): every pair of camps from the SAME
    # founding must sit at least `@min_camp_spacing` (3) raw-adjacency
    # hexes apart — near-to-near, far-to-far, and near-to-far.
    test "no two camps from the same founding land within the minimum spacing" do
      {home, city_tile} = home_region_and_city_tile()

      for seed <- [{@seed, city_tile}, {@seed, :other_founding}, {@seed, :a_third}] do
        tiles = Camps.place_wilderness(world(), city_tile, home, MapSet.new(), MapSet.new(), seed)

        for a <- tiles, b <- tiles, a < b do
          assert hex_distance(a, b) >= 3,
                 "camps #{a} and #{b} landed #{hex_distance(a, b)} hexes apart (seed #{inspect(seed)})"
        end
      end
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

  # Raw mesh-adjacency (hex) distance between two tiles — smallest ring
  # depth from `a` that contains `b`. Used only by the spacing
  # regression above; the module under test has no public "distance
  # between two arbitrary tiles" read of its own (it only ever grows a
  # ring around a single, known start).
  defp hex_distance(a, b) do
    Enum.find(0..30, fn depth -> MapSet.member?(ring(a, depth), b) end)
  end

  defp ring(start, 0), do: MapSet.new([start])

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
