defmodule BrokenOaths.Worlds.GeneratorTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.Generator

  @test_seed 42
  @small_width 20
  @small_height 15

  describe "generate_terrain_map/3" do
    test "returns a map with entries for every hex" do
      terrain_map = Generator.generate_terrain_map(@test_seed, @small_width, @small_height)
      assert map_size(terrain_map) == @small_width * @small_height
    end

    test "all keys are {q, r} tuples within bounds" do
      terrain_map = Generator.generate_terrain_map(@test_seed, @small_width, @small_height)

      for {{q, r}, _terrain} <- terrain_map do
        assert q >= 0 and q < @small_width, "q=#{q} out of bounds"
        assert r >= 0 and r < @small_height, "r=#{r} out of bounds"
      end
    end

    test "all values are valid terrain atoms" do
      valid = ~w(ocean shallow_water beach grassland plains forest hills mountains)a
      terrain_map = Generator.generate_terrain_map(@test_seed, @small_width, @small_height)

      for {_coord, terrain} <- terrain_map do
        assert terrain in valid, "Invalid terrain: #{inspect(terrain)}"
      end
    end

    test "is deterministic - same seed produces same map" do
      map1 = Generator.generate_terrain_map(@test_seed, @small_width, @small_height)
      map2 = Generator.generate_terrain_map(@test_seed, @small_width, @small_height)
      assert map1 == map2
    end

    test "different seeds produce different maps" do
      map1 = Generator.generate_terrain_map(42, @small_width, @small_height)
      map2 = Generator.generate_terrain_map(43, @small_width, @small_height)
      refute map1 == map2
    end

    test "produces terrain variety (not all one type)" do
      terrain_map = Generator.generate_terrain_map(@test_seed, 50, 50)
      terrain_types = terrain_map |> Map.values() |> Enum.uniq()
      assert length(terrain_types) >= 3, "Expected at least 3 terrain types, got: #{inspect(terrain_types)}"
    end

    test "generates full-size world without error" do
      terrain_map = Generator.generate_terrain_map(@test_seed, 200, 150)
      assert map_size(terrain_map) == 30_000
    end
  end

  describe "generate_hex_terrain/3" do
    test "returns a valid terrain atom" do
      valid = ~w(ocean shallow_water beach grassland plains forest hills mountains)a
      terrain = Generator.generate_hex_terrain(@test_seed, 10, 10)
      assert terrain in valid
    end

    test "matches generate_terrain_map for the same coordinates" do
      terrain_map = Generator.generate_terrain_map(@test_seed, @small_width, @small_height)

      # Check several random hexes
      for q <- [0, 5, 10, 19], r <- [0, 7, 14] do
        single = Generator.generate_hex_terrain(@test_seed, q, r)
        from_map = Map.get(terrain_map, {q, r})
        assert single == from_map, "Mismatch at (#{q}, #{r}): #{single} vs #{from_map}"
      end
    end
  end

  describe "terrain_stats/1" do
    test "returns stats for each terrain type present" do
      terrain_map = Generator.generate_terrain_map(@test_seed, @small_width, @small_height)
      stats = Generator.terrain_stats(terrain_map)

      assert is_list(stats)
      assert length(stats) > 0

      for {terrain, count, pct} <- stats do
        assert is_atom(terrain)
        assert is_integer(count)
        assert count > 0
        assert is_float(pct)
        assert pct > 0.0 and pct <= 100.0
      end
    end

    test "percentages sum to approximately 100" do
      terrain_map = Generator.generate_terrain_map(@test_seed, @small_width, @small_height)
      stats = Generator.terrain_stats(terrain_map)
      total_pct = stats |> Enum.map(fn {_, _, pct} -> pct end) |> Enum.sum()
      assert_in_delta total_pct, 100.0, 1.0
    end

    test "counts sum to total hex count" do
      terrain_map = Generator.generate_terrain_map(@test_seed, @small_width, @small_height)
      stats = Generator.terrain_stats(terrain_map)
      total_count = stats |> Enum.map(fn {_, count, _} -> count end) |> Enum.sum()
      assert total_count == @small_width * @small_height
    end

    test "sorted by count descending" do
      terrain_map = Generator.generate_terrain_map(@test_seed, @small_width, @small_height)
      stats = Generator.terrain_stats(terrain_map)
      counts = Enum.map(stats, fn {_, count, _} -> count end)
      assert counts == Enum.sort(counts, :desc)
    end
  end

  describe "find_spawn_points/3" do
    test "returns requested number of points" do
      terrain_map = Generator.generate_terrain_map(@test_seed, 50, 50)
      points = Generator.find_spawn_points(terrain_map, 3, 50)
      assert length(points) == 3
    end

    test "all spawn points are on grassland" do
      terrain_map = Generator.generate_terrain_map(@test_seed, 50, 50)
      points = Generator.find_spawn_points(terrain_map, 3, 50)

      for point <- points do
        assert Map.get(terrain_map, point) == :grassland,
               "Spawn at #{inspect(point)} is #{Map.get(terrain_map, point)}, expected grassland"
      end
    end

    test "returns fewer points if not enough grassland" do
      # With a tiny map there might not be enough grassland
      terrain_map = Generator.generate_terrain_map(@test_seed, 5, 5)
      points = Generator.find_spawn_points(terrain_map, 100, 5)
      # Should return what's available, not crash
      assert is_list(points)
    end

    test "spawn points are spread apart" do
      terrain_map = Generator.generate_terrain_map(@test_seed, 100, 100)
      points = Generator.find_spawn_points(terrain_map, 4, 100)

      if length(points) >= 2 do
        # Check that no two points are adjacent
        for [p1, p2] <- Enum.chunk_every(points, 2, 1, :discard) do
          {q1, r1} = p1
          {q2, r2} = p2
          dist = abs(q1 - q2) + abs(r1 - r2)
          assert dist > 2, "Spawn points too close: #{inspect(p1)} and #{inspect(p2)}"
        end
      end
    end
  end
end
