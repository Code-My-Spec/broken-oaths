defmodule BrokenOaths.Worlds.GeneratorTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.Generator
  alias BrokenOaths.Worlds.Globe

  @test_seed 42

  describe "generate_terrain_map/2 (globe)" do
    setup do
      %{mesh: Globe.build(8)}
    end

    test "returns an entry for every tile id", %{mesh: mesh} do
      terrain_map = Generator.generate_terrain_map(@test_seed, mesh)
      assert map_size(terrain_map) == Globe.tile_count(8)
      assert Enum.sort(Map.keys(terrain_map)) == Enum.sort(Map.keys(mesh.tiles))
    end

    test "all values are valid terrain atoms", %{mesh: mesh} do
      valid =
        ~w(ocean shallow_water beach grassland plains forest hills mountains tundra snow jungle swamp desert)a

      terrain_map = Generator.generate_terrain_map(@test_seed, mesh)

      for {_id, terrain} <- terrain_map do
        assert terrain in valid, "Invalid terrain: #{inspect(terrain)}"
      end
    end

    test "all 12 pentagons are mountains", %{mesh: mesh} do
      terrain_map = Generator.generate_terrain_map(@test_seed, mesh)

      pentagons = Enum.filter(Map.values(mesh.tiles), & &1.pentagon?)
      assert length(pentagons) == 12

      for tile <- pentagons do
        assert terrain_map[tile.id] == :mountains
      end
    end

    test "is deterministic - same seed produces same map", %{mesh: mesh} do
      assert Generator.generate_terrain_map(@test_seed, mesh) ==
               Generator.generate_terrain_map(@test_seed, mesh)
    end

    test "different seeds produce different maps", %{mesh: mesh} do
      refute Generator.generate_terrain_map(@test_seed, mesh) ==
               Generator.generate_terrain_map(@test_seed + 1, mesh)
    end

    test "produces terrain variety", %{mesh: mesh} do
      terrain_map = Generator.generate_terrain_map(@test_seed, mesh)
      types = terrain_map |> Map.values() |> Enum.uniq()
      assert length(types) >= 3, "Expected at least 3 terrain types, got #{inspect(types)}"
    end
  end

  describe "generate_maps/2" do
    setup do
      %{mesh: Globe.build(8)}
    end

    test "elevation covers every tile in [0, 1] and is deterministic", %{mesh: mesh} do
      %{elevation: elevation} = Generator.generate_maps(@test_seed, mesh)

      assert map_size(elevation) == Globe.tile_count(8)

      for {_id, e} <- elevation do
        assert e >= 0.0 and e <= 1.0
      end

      assert Generator.generate_maps(@test_seed, mesh).elevation == elevation
    end

    test "poles are frozen, equator is not", %{mesh: mesh} do
      %{terrain: terrain} = Generator.generate_maps(@test_seed, mesh)

      for tile <- Map.values(mesh.tiles), not tile.pentagon? do
        {_x, _y, z} = tile.center

        cond do
          abs(z) > 0.97 ->
            assert terrain[tile.id] == :snow

          abs(z) < 0.25 ->
            refute terrain[tile.id] in [:snow, :tundra]

          true ->
            :ok
        end
      end
    end

    test "pentagons peak; terrain agrees with generate_terrain_map", %{mesh: mesh} do
      %{terrain: terrain, elevation: elevation} = Generator.generate_maps(@test_seed, mesh)

      for tile <- Map.values(mesh.tiles), tile.pentagon? do
        assert elevation[tile.id] == 0.95
        assert terrain[tile.id] == :mountains
      end

      assert terrain == Generator.generate_terrain_map(@test_seed, mesh)
    end
  end

  describe "find_spawn_points/3 (globe)" do
    setup do
      mesh = Globe.build(8)
      %{mesh: mesh, terrain_map: Generator.generate_terrain_map(@test_seed, mesh)}
    end

    test "returns requested number of grassland tiles", %{mesh: mesh, terrain_map: tm} do
      points = Generator.find_spawn_points(tm, mesh, 3)
      assert length(points) == 3

      for id <- points do
        assert tm[id] == :grassland
      end
    end

    test "spawn points are spread apart", %{mesh: mesh, terrain_map: tm} do
      points = Generator.find_spawn_points(tm, mesh, 4)

      for a <- points, b <- points, a != b do
        ca = Globe.tile(mesh, a).center
        cb = Globe.tile(mesh, b).center
        {ax, ay, az} = ca
        {bx, by, bz} = cb
        dx = ax - bx
        dy = ay - by
        dz = az - bz
        chord = :math.sqrt(dx * dx + dy * dy + dz * dz)

        # At least a few tiles apart (tile spacing at f=8 ≈ 0.138 chord)
        assert chord > 0.2, "spawn points #{a} and #{b} too close (chord #{chord})"
      end
    end

    test "is deterministic", %{mesh: mesh, terrain_map: tm} do
      assert Generator.find_spawn_points(tm, mesh, 3) ==
               Generator.find_spawn_points(tm, mesh, 3)
    end
  end

  describe "terrain_stats/1" do
    setup do
      mesh = Globe.build(8)
      %{terrain_map: Generator.generate_terrain_map(@test_seed, mesh)}
    end

    test "returns stats for each terrain type present", %{terrain_map: terrain_map} do
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

    test "percentages sum to approximately 100", %{terrain_map: terrain_map} do
      stats = Generator.terrain_stats(terrain_map)
      total_pct = stats |> Enum.map(fn {_, _, pct} -> pct end) |> Enum.sum()
      assert_in_delta total_pct, 100.0, 1.0
    end

    test "counts sum to total tile count", %{terrain_map: terrain_map} do
      stats = Generator.terrain_stats(terrain_map)
      total_count = stats |> Enum.map(fn {_, count, _} -> count end) |> Enum.sum()
      assert total_count == Globe.tile_count(8)
    end

    test "sorted by count descending", %{terrain_map: terrain_map} do
      stats = Generator.terrain_stats(terrain_map)
      counts = Enum.map(stats, fn {_, count, _} -> count end)
      assert counts == Enum.sort(counts, :desc)
    end
  end
end
