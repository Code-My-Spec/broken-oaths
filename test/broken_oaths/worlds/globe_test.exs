defmodule BrokenOaths.Worlds.GlobeTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Globe.Tile

  @frequencies [2, 3, 8]

  describe "tile_count/1" do
    test "follows 10f² + 2" do
      assert Globe.tile_count(1) == 12
      assert Globe.tile_count(2) == 42
      assert Globe.tile_count(3) == 92
      assert Globe.tile_count(8) == 642
      assert Globe.tile_count(54) == 29_162
    end
  end

  describe "build/1 structure" do
    test "produces 10f² + 2 tiles with contiguous ids" do
      for f <- @frequencies do
        mesh = Globe.build(f)
        n = Globe.tile_count(f)
        assert map_size(mesh.tiles) == n
        assert Enum.sort(Map.keys(mesh.tiles)) == Enum.to_list(0..(n - 1))
      end
    end

    test "has exactly 12 pentagons; all other tiles are hexagons" do
      for f <- @frequencies do
        mesh = Globe.build(f)
        {pentagons, hexagons} = Enum.split_with(Map.values(mesh.tiles), & &1.pentagon?)

        assert length(pentagons) == 12
        assert length(hexagons) == Globe.tile_count(f) - 12

        for %Tile{} = p <- pentagons do
          assert length(p.corners) == 5
          assert length(p.neighbors) == 5
        end

        for %Tile{} = h <- hexagons do
          assert length(h.corners) == 6
          assert length(h.neighbors) == 6
        end
      end
    end

    test "tile 0 is the north pole pentagon; south pole pentagon exists" do
      mesh = Globe.build(3)

      north = Globe.tile(mesh, 0)
      assert north.pentagon?
      assert_in_delta elem(north.center, 2), 1.0, 1.0e-12

      south =
        Enum.find(Map.values(mesh.tiles), fn t ->
          elem(t.center, 2) < -0.999999
        end)

      assert south, "no south pole tile found"
      assert south.pentagon?
    end

    test "pentagons sit at the poles and at ±26.57° latitude" do
      mesh = Globe.build(8)

      lats =
        mesh.tiles
        |> Map.values()
        |> Enum.filter(& &1.pentagon?)
        |> Enum.map(fn t -> elem(Globe.latlon(t.center), 0) end)
        |> Enum.sort()

      ring = :math.atan(0.5) * 180.0 / :math.pi()
      expected = Enum.sort([-90.0, 90.0] ++ List.duplicate(-ring, 5) ++ List.duplicate(ring, 5))

      for {actual, exp} <- Enum.zip(lats, expected) do
        assert_in_delta actual, exp, 1.0e-6
      end
    end
  end

  describe "build/1 geometry" do
    test "all centers and corners are unit vectors" do
      mesh = Globe.build(3)

      for %Tile{center: c, corners: corners} <- Map.values(mesh.tiles) do
        assert_in_delta norm(c), 1.0, 1.0e-9

        for corner <- corners do
          assert_in_delta norm(corner), 1.0, 1.0e-9
        end
      end
    end

    test "corners are local to the tile" do
      for f <- @frequencies do
        mesh = Globe.build(f)
        # Center-to-center tile spacing is ~ (icosa edge arc)/f; corners lie
        # well within one spacing of the center.
        max_chord = 2 * 1.107149 / f

        for %Tile{center: c, corners: corners} <- Map.values(mesh.tiles),
            corner <- corners do
          assert chord(c, corner) < max_chord
        end
      end
    end

    test "corners are sorted by ascending tangent-plane angle (including pole tiles)" do
      mesh = Globe.build(3)

      for %Tile{center: {nx, ny, nz} = n, corners: corners} <- Map.values(mesh.tiles) do
        ref = if abs(nz) > 0.9, do: {1.0, 0.0, 0.0}, else: {0.0, 0.0, 1.0}
        e1 = normalize(sub(ref, scale(n, dot(ref, n))))
        e2 = cross(n, e1)

        angles = Enum.map(corners, fn p -> :math.atan2(dot(p, e2), dot(p, e1)) end)

        assert angles == Enum.sort(angles),
               "corners of tile at #{inspect({nx, ny, nz})} not angle-sorted"
      end
    end
  end

  describe "build/1 topology" do
    test "neighbor relation is symmetric" do
      for f <- @frequencies do
        mesh = Globe.build(f)

        for %Tile{id: id, neighbors: neighbors} <- Map.values(mesh.tiles),
            n <- neighbors do
          assert id in Globe.tile(mesh, n).neighbors,
                 "tile #{n} does not list #{id} back as neighbor (f=#{f})"
        end
      end
    end

    test "adjacent tiles share exactly two corners" do
      mesh = Globe.build(3)

      for %Tile{id: id, corners: corners, neighbors: neighbors} <- Map.values(mesh.tiles),
          n <- neighbors,
          n > id do
        # Corners come from a shared centroid map, so shared corners are
        # bit-identical tuples.
        shared =
          MapSet.intersection(
            MapSet.new(corners),
            MapSet.new(Globe.tile(mesh, n).corners)
          )

        assert MapSet.size(shared) == 2,
               "tiles #{id} and #{n} share #{MapSet.size(shared)} corners, expected 2"
      end
    end

    test "the whole mesh is connected" do
      mesh = Globe.build(2)

      reachable = bfs(mesh, 0)
      assert MapSet.size(reachable) == Globe.tile_count(2)
    end
  end

  describe "determinism and caching" do
    test "build/1 is deterministic" do
      assert Globe.build(3) == Globe.build(3)
    end

    test "get/1 caches and returns the built mesh" do
      mesh = Globe.get(2)
      assert mesh == Globe.build(2)
      assert Globe.get(2) == mesh
    end
  end

  describe "latlon/1" do
    test "poles and equator" do
      assert {lat, _} = Globe.latlon({0.0, 0.0, 1.0})
      assert_in_delta lat, 90.0, 1.0e-9

      assert {lat, lon} = Globe.latlon({1.0, 0.0, 0.0})
      assert_in_delta lat, 0.0, 1.0e-9
      assert_in_delta lon, 0.0, 1.0e-9

      assert {_, lon} = Globe.latlon({0.0, 1.0, 0.0})
      assert_in_delta lon, 90.0, 1.0e-9
    end
  end

  @tag :slow
  test "full-size world builds with the right tile count" do
    mesh = Globe.build(54)
    assert map_size(mesh.tiles) == 29_162
    assert Enum.count(Map.values(mesh.tiles), & &1.pentagon?) == 12
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp bfs(mesh, start) do
    do_bfs(mesh, [start], MapSet.new([start]))
  end

  defp do_bfs(_mesh, [], seen), do: seen

  defp do_bfs(mesh, [id | rest], seen) do
    new = Enum.reject(Globe.tile(mesh, id).neighbors, &MapSet.member?(seen, &1))
    do_bfs(mesh, rest ++ new, Enum.reduce(new, seen, &MapSet.put(&2, &1)))
  end

  defp norm({x, y, z}), do: :math.sqrt(x * x + y * y + z * z)

  defp chord(a, b) do
    {ax, ay, az} = a
    {bx, by, bz} = b
    norm({ax - bx, ay - by, az - bz})
  end

  defp normalize({x, y, z} = v) do
    len = norm(v)
    {x / len, y / len, z / len}
  end

  defp sub({ax, ay, az}, {bx, by, bz}), do: {ax - bx, ay - by, az - bz}
  defp scale({x, y, z}, s), do: {x * s, y * s, z * s}
  defp dot({ax, ay, az}, {bx, by, bz}), do: ax * bx + ay * by + az * bz

  defp cross({ax, ay, az}, {bx, by, bz}),
    do: {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}
end
