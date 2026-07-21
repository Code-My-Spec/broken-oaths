defmodule BrokenOaths.Worlds.GeneratorTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.Generator
  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Terrain

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

    test "all values are valid Terrain structs", %{mesh: mesh} do
      bases = ~w(ocean coast grassland plains desert tundra snow)a
      reliefs = ~w(flat hills mountains)a
      features = [nil, :woods, :rainforest, :marsh, :ice]

      terrain_map = Generator.generate_terrain_map(@test_seed, mesh)

      for {_id, %Terrain{} = t} <- terrain_map do
        assert t.base in bases, "Invalid base: #{inspect(t)}"
        assert t.relief in reliefs
        assert t.feature in features
        # Water is always flat; features never sit on mountains
        if Terrain.water?(t), do: assert(t.relief == :flat)
        if t.relief == :mountains, do: assert(t.feature == nil)
      end
    end

    test "all 12 pentagons are mountains relief", %{mesh: mesh} do
      terrain_map = Generator.generate_terrain_map(@test_seed, mesh)

      pentagons = Enum.filter(Map.values(mesh.tiles), & &1.pentagon?)
      assert length(pentagons) == 12

      for tile <- pentagons do
        assert terrain_map[tile.id].relief == :mountains
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

  describe "hills relief distribution (regression for QA issue 9ccba1be)" do
    # Sheep and Stone resources are gated to hills-relief land (see
    # Worlds.Resources). The original elevation cutoff (>= 0.74) produced
    # hills at ~0% of land because the 6-octave fBm noise rarely climbs
    # that high. This locks the widened band (>= 0.60) to a playable
    # fraction of land, without touching the water/land boundary or the
    # mountains cutoff.
    test "hills relief appears at a playable rate across seeds" do
      mesh = Globe.build(16)

      for seed <- [42, 123, 4242] do
        terrain_map = Generator.generate_terrain_map(seed, mesh)

        land = terrain_map |> Map.values() |> Enum.reject(&Terrain.water?/1)
        land_count = length(land)
        hills_count = Enum.count(land, &(&1.relief == :hills))
        hills_pct = hills_count / land_count * 100

        assert hills_count > 0,
               "seed #{seed}: expected some hills relief on land, got none " <>
                 "(land_count=#{land_count})"

        assert hills_pct >= 5.0 and hills_pct <= 20.0,
               "seed #{seed}: hills relief is #{Float.round(hills_pct, 1)}% of land, " <>
                 "outside the playable 5-20% band"
      end
    end

    test "mountains relief is untouched by the hills widening" do
      mesh = Globe.build(16)

      for seed <- [42, 123, 4242] do
        terrain_map = Generator.generate_terrain_map(seed, mesh)
        land = terrain_map |> Map.values() |> Enum.reject(&Terrain.water?/1)
        land_count = length(land)
        mountains_pct = Enum.count(land, &(&1.relief == :mountains)) / land_count * 100

        # Mountains cutoff (elevation >= 0.88) is unchanged; only the
        # pentagon-forced peaks plus rare natural peaks should register,
        # historically well under 5% of land.
        assert mountains_pct < 5.0,
               "seed #{seed}: mountains relief grew to #{Float.round(mountains_pct, 1)}% " <>
                 "of land — the mountains threshold should not have moved"
      end
    end
  end

  describe "coast is the land-adjacent water ring (Civ 6 model)" do
    # A water tile is COAST when it touches at least one land tile,
    # otherwise it stays OCEAN. Coast can never form a standalone blob away
    # from a coastline. These assertions run over real generator output and
    # find tiles from that output rather than hand-guessing ids.
    setup do
      mesh = Globe.build(16)
      %{mesh: mesh, terrain_map: Generator.generate_terrain_map(@test_seed, mesh)}
    end

    defp land?(%Terrain{} = t), do: not Terrain.water?(t)

    defp neighbor_bases(mesh, terrain_map, id) do
      mesh.tiles[id].neighbors |> Enum.map(&terrain_map[&1])
    end

    test "every coast tile has at least one land neighbour (anti-blob invariant)",
         %{mesh: mesh, terrain_map: tm} do
      coast_ids = for {id, %Terrain{base: :coast}} <- tm, do: id
      assert coast_ids != [], "expected the generated world to have some coast"

      for id <- coast_ids do
        neighbours = neighbor_bases(mesh, tm, id)

        assert Enum.any?(neighbours, &land?/1),
               "coast tile #{id} has no land neighbour (a coast blob) — " <>
                 "neighbour bases: #{inspect(Enum.map(neighbours, & &1.base))}"
      end
    end

    test "a water tile adjacent to land is classified coast", %{mesh: mesh, terrain_map: tm} do
      # Pick a real ocean-or-coast tile that touches land, straight from output.
      land_adjacent_water =
        Enum.find(tm, fn {id, t} ->
          Terrain.water?(t) and Enum.any?(neighbor_bases(mesh, tm, id), &land?/1)
        end)

      assert {id, _} = land_adjacent_water,
             "expected at least one water tile touching land in the generated world"

      assert tm[id].base == :coast,
             "water tile #{id} touches land but is #{tm[id].base}, not coast"
    end

    test "a water tile with only water neighbours stays ocean", %{mesh: mesh, terrain_map: tm} do
      # Deep-ocean tile: water, and every neighbour is water too.
      deep_water =
        Enum.find(tm, fn {id, t} ->
          Terrain.water?(t) and Enum.all?(neighbor_bases(mesh, tm, id), &Terrain.water?/1)
        end)

      assert {id, _} = deep_water,
             "expected at least one fully water-surrounded tile in the generated world"

      assert tm[id].base == :ocean,
             "water tile #{id} has only water neighbours but is #{tm[id].base}, not ocean"
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
            assert terrain[tile.id].base == :snow or terrain[tile.id].feature == :ice

          abs(z) < 0.25 ->
            refute terrain[tile.id].base in [:snow, :tundra]

          true ->
            :ok
        end
      end
    end

    test "pentagons peak; terrain agrees with generate_terrain_map", %{mesh: mesh} do
      %{terrain: terrain, elevation: elevation} = Generator.generate_maps(@test_seed, mesh)

      for tile <- Map.values(mesh.tiles), tile.pentagon? do
        assert elevation[tile.id] == 0.95
        assert terrain[tile.id].relief == :mountains
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
        assert tm[id].base == :grassland
        refute tm[id].relief == :mountains
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
        assert %Terrain{} = terrain
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
