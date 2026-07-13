defmodule BrokenOaths.Worlds.FacetsTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.{Facets, Globe}

  @frequency 8

  setup_all do
    %{facets: Facets.build(@frequency)}
  end

  test "one facet per tile, sorted by id", %{facets: facets} do
    assert length(facets) == Globe.tile_count(@frequency)
    assert Enum.map(facets, & &1.id) == Enum.to_list(0..(Globe.tile_count(@frequency) - 1))
  end

  test "12 pentagon facets", %{facets: facets} do
    assert Enum.count(facets, & &1.pentagon?) == 12
  end

  test "boxes have sane dimensions", %{facets: facets} do
    # Tile chord at f=8 ≈ 0.138 · r0 ≈ 97px; boxes must be positive and local
    for f <- facets do
      assert f.w >= 1 and f.w < Facets.r0()
      assert f.h >= 1 and f.h < Facets.r0()
    end
  end

  test "clip polygons have 5 or 6 points, all within [0, 100]%", %{facets: facets} do
    for f <- facets do
      points = Regex.scan(~r/([\d.]+)% ([\d.]+)%/, f.clip)
      assert length(points) in [5, 6]
      assert length(points) == 5 == f.pentagon?

      for [_, x, y] <- points do
        assert String.to_float(x) >= 0.0 and String.to_float(x) <= 100.0
        assert String.to_float(y) >= 0.0 and String.to_float(y) <= 100.0
      end
    end
  end

  test "matrices are rigid placements on the r0 sphere", %{facets: facets} do
    r0 = Facets.r0()

    for f <- Enum.take_every(facets, 37) do
      nums =
        Regex.run(~r/matrix3d\((.+)\)/, f.matrix)
        |> List.last()
        |> String.split(",")
        |> Enum.map(fn s ->
          s = String.trim(s)

          case Float.parse(s) do
            {v, ""} -> v
          end
        end)

      assert length(nums) == 16

      [tx, ty, tz, 0.0, bx, by, bz, 0.0, nx, ny, nz, 0.0, px, py, pz, 1.0] = nums

      # Orthonormal axis columns
      assert_in_delta tx * tx + ty * ty + tz * tz, 1.0, 1.0e-4
      assert_in_delta bx * bx + by * by + bz * bz, 1.0, 1.0e-4
      assert_in_delta nx * nx + ny * ny + nz * nz, 1.0, 1.0e-4
      assert_in_delta tx * bx + ty * by + tz * bz, 0.0, 1.0e-4

      # T × B = N (front-facing for backface culling)
      assert_in_delta ty * bz - tz * by, nx, 1.0e-4
      assert_in_delta tz * bx - tx * bz, ny, 1.0e-4
      assert_in_delta tx * by - ty * bx, nz, 1.0e-4

      # Translation sits at roughly r0 from the origin (facet plane is the
      # chord plane, slightly inside the sphere, offset by the bbox corner)
      dist = :math.sqrt(px * px + py * py + pz * pz)
      assert dist > 0.9 * r0 and dist < 1.02 * r0
    end
  end

  test "build is deterministic and get/1 caches", %{facets: facets} do
    assert Facets.build(@frequency) == facets
    assert Facets.get(@frequency) == facets
    assert Facets.get(@frequency) == facets
  end
end
