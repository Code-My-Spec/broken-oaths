defmodule BrokenOaths.Worlds.RegionsTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @frequency 8
  @seed 424_242
  @total_tiles Globe.tile_count(@frequency)

  defp world(seed \\ @seed, frequency \\ @frequency) do
    %World{seed: seed, frequency: frequency}
  end

  describe "region_of/2" do
    test "maps a region's own tiles back to its region id" do
      w = world()
      %{regions: regions} = Regions.partition(w)

      for {rid, tiles} <- regions, tile <- Enum.take(tiles, 3) do
        assert Regions.region_of(w, tile) == rid
      end
    end

    test "returns nil for a tile in no region (deep ocean or out of range)" do
      w = world()
      %{deep_ocean: deep_ocean} = Regions.partition(w)

      for tile <- Enum.take(deep_ocean, 3) do
        assert Regions.region_of(w, tile) == nil
      end

      assert Regions.region_of(w, -1) == nil
    end
  end

  describe "partition/1" do
    test "is deterministic for a given seed and frequency" do
      first = Regions.partition(world())
      second = Regions.partition(world())

      assert first == second
      assert map_size(first.regions) > 0
    end

    test "regions and deep ocean cover every tile exactly once" do
      %{regions: regions, deep_ocean: deep_ocean} = Regions.partition(world())

      all = Map.values(regions) |> List.flatten() |> Kernel.++(deep_ocean)

      assert length(all) == @total_tiles
      assert length(Enum.uniq(all)) == @total_tiles
      assert Enum.sort(all) == Enum.to_list(0..(@total_tiles - 1))
    end

    test "no region contains a deep-ocean tile; deep ocean contains only deep-ocean tiles" do
      w = world()
      %{regions: regions, deep_ocean: deep_ocean} = Regions.partition(w)

      for {_id, tiles} <- regions, tile <- tiles do
        assert Regions.tile_class(w, tile) != :deep_ocean
      end

      for tile <- deep_ocean do
        assert Regions.tile_class(w, tile) == :deep_ocean
      end
    end

    test "every region tile is land, mountain, or coastal water" do
      w = world()
      %{regions: regions} = Regions.partition(w)

      classes =
        for {_id, tiles} <- regions, tile <- tiles, do: Regions.tile_class(w, tile)

      for class <- classes, do: assert(class in [:land, :mountain, :coastal_water])
      # Anchor: at frequency 8 with this seed, both kinds genuinely occur.
      assert :mountain in classes
      assert :coastal_water in classes
    end

    test "each region is contiguous under mesh adjacency" do
      w = world()
      %{regions: regions} = Regions.partition(w)

      for {region_id, tiles} <- regions do
        tile_set = MapSet.new(tiles)
        reached = flood_within(hd(tiles), tile_set, w)

        assert MapSet.size(reached) == length(tiles),
               "region #{region_id} is not contiguous: reached #{MapSet.size(reached)} of #{length(tiles)} tiles"
      end
    end

    test "region ids are stable integers starting at 0" do
      %{regions: regions} = Regions.partition(world())

      ids = regions |> Map.keys() |> Enum.sort()
      assert ids == Enum.to_list(0..(map_size(regions) - 1))
    end
  end

  describe "spawnable/1" do
    test "only returns regions meeting the 175-tile habitability floor" do
      w = world()
      %{regions: regions} = Regions.partition(w)
      spawnable = Regions.spawnable(w)

      assert spawnable != []

      for region_id <- spawnable do
        assert length(Map.fetch!(regions, region_id)) >= 175
      end

      excluded = Map.keys(regions) -- spawnable

      for region_id <- excluded do
        assert length(Map.fetch!(regions, region_id)) < 175
      end
    end
  end

  describe "tile_class/2" do
    test "classifies every tile as one of the four classes" do
      w = world()
      mesh = Globe.get(@frequency)

      for id <- Map.keys(mesh.tiles) do
        assert Regions.tile_class(w, id) in [:land, :mountain, :coastal_water, :deep_ocean]
      end
    end

    test "a deep-ocean tile has no land or mountain neighbor" do
      # @seed's small (642-tile) globe happens to have no deep ocean at all —
      # every water tile ends up within one hop of land. Seed 10 does.
      w = world(10)
      mesh = Globe.get(@frequency)

      deep_ocean_tile =
        mesh.tiles
        |> Map.keys()
        |> Enum.find(fn id -> Regions.tile_class(w, id) == :deep_ocean end)

      refute is_nil(deep_ocean_tile)

      for neighbor <- Regions.adjacent_tiles(w, deep_ocean_tile) do
        refute Regions.tile_class(w, neighbor) in [:land, :mountain]
      end
    end

    test "a coastal-water tile has at least one non-water neighbor" do
      w = world()
      mesh = Globe.get(@frequency)

      coastal_tile =
        mesh.tiles
        |> Map.keys()
        |> Enum.find(fn id -> Regions.tile_class(w, id) == :coastal_water end)

      refute is_nil(coastal_tile)

      assert Enum.any?(Regions.adjacent_tiles(w, coastal_tile), fn n ->
               Regions.tile_class(w, n) in [:land, :mountain]
             end)
    end
  end

  describe "adjacent_tiles/2" do
    test "matches the globe mesh neighbors" do
      w = world()
      mesh = Globe.get(@frequency)

      for id <- Enum.take(Map.keys(mesh.tiles), 20) do
        assert Regions.adjacent_tiles(w, id) == Globe.tile(mesh, id).neighbors
      end
    end
  end

  # Story 927 "Workers chop woods and rainforest" — `terrain/3`'s own
  # worker-cleared overlay (`state.cleared_features`, see
  # `BrokenOaths.Cities.Improvement.chop/3`).
  describe "terrain/3 (story 927 — the worker-cleared overlay)" do
    test "an uncleared tile is untouched — identical to terrain/2" do
      w = world()
      tile = a_land_tile(w)
      assert Regions.terrain(w, tile, MapSet.new()) == Regions.terrain(w, tile)
    end

    test "a cleared tile loses its feature but keeps base/relief" do
      w = world()
      tile = a_land_tile(w)
      raw = Regions.terrain(w, tile)

      cleared = Regions.terrain(w, tile, MapSet.new([tile]))
      assert cleared.feature == nil
      assert cleared.base == raw.base
      assert cleared.relief == raw.relief
    end

    test "only clears the tiles actually in cleared_features — a sibling tile is untouched" do
      w = world()
      [tile_a, tile_b] = Enum.take(land_tiles(w), 2)

      assert Regions.terrain(w, tile_a, MapSet.new([tile_b])) == Regions.terrain(w, tile_a)
    end

    test "clearing an already-featureless tile is a no-op" do
      w = world()

      tile =
        Enum.find(land_tiles(w), &(Regions.terrain(w, &1).feature == nil))

      assert Regions.terrain(w, tile, MapSet.new([tile])) == Regions.terrain(w, tile)
    end
  end

  defp land_tiles(w) do
    for t <- 0..(@total_tiles - 1), Regions.tile_class(w, t) == :land, do: t
  end

  defp a_land_tile(w), do: w |> land_tiles() |> hd()

  # Flood-fills `tile_set` (mesh adjacency) starting from `start`, returning
  # the reached subset — used to assert a region is a single connected blob.
  defp flood_within(start, tile_set, w) do
    do_flood([start], MapSet.new([start]), tile_set, w)
  end

  defp do_flood([], visited, _tile_set, _w), do: visited

  defp do_flood([id | rest], visited, tile_set, w) do
    {visited, discovered} =
      w
      |> Regions.adjacent_tiles(id)
      |> Enum.reduce({visited, []}, fn n, {v, acc} ->
        if MapSet.member?(tile_set, n) and not MapSet.member?(v, n) do
          {MapSet.put(v, n), [n | acc]}
        else
          {v, acc}
        end
      end)

    do_flood(discovered ++ rest, visited, tile_set, w)
  end
end
