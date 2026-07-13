defmodule BrokenOaths.Worlds.ProjectionTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.{Globe, Projection}

  @view %{yaw: 0.0, pitch: 0.0, scale: 350, cx: 480, cy: 350, w: 960, h: 700}

  describe "rotate/3" do
    test "identity view looks at (1, 0, 0)" do
      {vx, vy, vz} = Projection.rotate({1.0, 0.0, 0.0}, 0.0, 0.0)
      assert_in_delta vx, 0.0, 1.0e-12
      assert_in_delta vy, 0.0, 1.0e-12
      assert_in_delta vz, 1.0, 1.0e-12
    end

    test "north pole appears up at identity view" do
      {vx, vy, vz} = Projection.rotate({0.0, 0.0, 1.0}, 0.0, 0.0)
      assert_in_delta vx, 0.0, 1.0e-12
      assert_in_delta vy, 1.0, 1.0e-12
      assert_in_delta vz, 0.0, 1.0e-12
    end

    test "the point at (lat=pitch, lon=yaw) rotates to the view center" do
      for {lat, lon} <- [{0.3, 1.1}, {-0.9, 4.5}, {1.2, 0.0}, {0.0, :math.pi()}] do
        p = {
          :math.cos(lat) * :math.cos(lon),
          :math.cos(lat) * :math.sin(lon),
          :math.sin(lat)
        }

        {vx, vy, vz} = Projection.rotate(p, lon, lat)
        assert_in_delta vx, 0.0, 1.0e-12
        assert_in_delta vy, 0.0, 1.0e-12
        assert_in_delta vz, 1.0, 1.0e-12
      end
    end

    test "preserves length" do
      {px, py, pz} = p = {0.267261, 0.534522, 0.801784}
      {vx, vy, vz} = Projection.rotate(p, 0.7, -0.4)

      assert_in_delta :math.sqrt(vx * vx + vy * vy + vz * vz),
                      :math.sqrt(px * px + py * py + pz * pz),
                      1.0e-12
    end

    test "east of view center projects screen-right" do
      # A point slightly east (greater longitude) of the view center
      lon = 0.1
      p = {:math.cos(lon), :math.sin(lon), 0.0}
      {vx, _vy, _vz} = Projection.rotate(p, 0.0, 0.0)
      assert vx > 0.0
    end
  end

  describe "project/4" do
    test "view center lands on screen center" do
      assert Projection.project({0.0, 0.0, 1.0}, 350, 480, 350) == {480.0, 350.0}
    end

    test "screen y grows downward (view-space up is negated)" do
      {_sx, sy} = Projection.project({0.0, 0.5, 0.5}, 350, 480, 350)
      assert sy < 350.0
    end

    test "scale multiplies offsets" do
      {sx, sy} = Projection.project({0.5, -0.25, 0.0}, 100, 0, 0)
      assert_in_delta sx, 50.0, 1.0e-12
      assert_in_delta sy, 25.0, 1.0e-12
    end
  end

  describe "visible_tiles/3" do
    setup do
      mesh = Globe.build(3)
      terrain = Map.new(Map.keys(mesh.tiles), &{&1, :grassland})
      %{mesh: mesh, terrain: terrain}
    end

    test "culls the rear hemisphere", %{mesh: mesh, terrain: terrain} do
      rendered = Projection.visible_tiles(mesh, terrain, @view)
      rendered_ids = MapSet.new(rendered, & &1.id)

      # Roughly half the tiles visible; never more than a hemisphere + margin
      assert length(rendered) > 0
      assert length(rendered) < map_size(mesh.tiles)

      for tile <- Map.values(mesh.tiles) do
        {_, _, vz} = Projection.rotate(tile.center, @view.yaw, @view.pitch)

        if MapSet.member?(rendered_ids, tile.id) do
          assert vz > 0.0, "rear-facing tile #{tile.id} was rendered"
        end
      end
    end

    test "every rendered tile has sane geometry", %{mesh: mesh, terrain: terrain} do
      for t <- Projection.visible_tiles(mesh, terrain, @view) do
        assert t.width >= 1
        assert t.height >= 1
        assert t.terrain == :grassland

        # clip-path percentages all within [0, 100]
        percents =
          Regex.scan(~r/([\d.]+)%/, t.clip_path)
          |> Enum.map(fn [_, num] -> String.to_float(num) end)

        assert length(percents) in [10, 12]

        for p <- percents do
          assert p >= 0.0 and p <= 100.0
        end
      end
    end

    test "bounding boxes contain all projected corners", %{mesh: mesh, terrain: terrain} do
      rendered = Projection.visible_tiles(mesh, terrain, @view)

      for t <- rendered do
        tile = Globe.tile(mesh, t.id)

        for corner <- tile.corners do
          {sx, sy} =
            corner
            |> Projection.rotate(@view.yaw, @view.pitch)
            |> Projection.project(@view.scale, @view.cx, @view.cy)

          assert sx >= t.left - 0.001 and sx <= t.left + t.width + 0.001
          assert sy >= t.top - 0.001 and sy <= t.top + t.height + 0.001
        end
      end
    end

    test "rotating the view changes which tiles are visible", %{mesh: mesh, terrain: terrain} do
      front = MapSet.new(Projection.visible_tiles(mesh, terrain, @view), & &1.id)

      back =
        MapSet.new(
          Projection.visible_tiles(mesh, terrain, %{@view | yaw: :math.pi()}),
          & &1.id
        )

      refute MapSet.equal?(front, back)
    end

    test "zooming in shows fewer tiles (screen-bounds culling)", %{mesh: mesh, terrain: terrain} do
      far = Projection.visible_tiles(mesh, terrain, @view)
      near = Projection.visible_tiles(mesh, terrain, %{@view | scale: 4000})

      assert length(near) < length(far)
    end

    test "unknown terrain defaults to ocean", %{mesh: mesh} do
      rendered = Projection.visible_tiles(mesh, %{}, @view)
      assert Enum.all?(rendered, &(&1.terrain == :ocean))
    end
  end

  describe "arc/2" do
    test "zero for identical points" do
      assert_in_delta Projection.arc({1.0, 0.0, 0.0}, {1.0, 0.0, 0.0}), 0.0, 1.0e-12
    end

    test "pi for antipodes" do
      assert_in_delta Projection.arc({0.0, 0.0, 1.0}, {0.0, 0.0, -1.0}), :math.pi(), 1.0e-12
    end

    test "pi/2 for orthogonal points" do
      assert_in_delta Projection.arc({1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}),
                      :math.pi() / 2,
                      1.0e-12
    end
  end
end
