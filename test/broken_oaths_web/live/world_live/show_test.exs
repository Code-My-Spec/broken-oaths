defmodule BrokenOathsWeb.WorldLive.ShowTest do
  use BrokenOathsTest.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BrokenOaths.WorldsFixtures

  alias BrokenOaths.Worlds.{Globe, Projection}

  # Fixture worlds use frequency 8 (642 tiles) to keep tests fast.
  @frequency 8

  describe "Show" do
    setup do
      %{world: world_fixture(%{name: "Emerald Shores", seed: 12345})}
    end

    test "renders world with globe tiles", %{conn: conn, world: world} do
      {:ok, _view, html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      assert html =~ "Emerald Shores"
      assert html =~ "12345"
      # Should render tile cells with per-tile clip paths
      assert html =~ "hex-cell"
      assert html =~ "clip-path:polygon("
      assert html =~ "globe-disc"
    end

    test "shows world size as tile count", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      html = open_sidebar(view)
      assert html =~ "GP(#{@frequency})"
      assert html =~ "#{Globe.tile_count(@frequency)} tiles"
    end

    test "shows terrain stats", %{conn: conn, world: world} do
      {:ok, _view, html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      # Stats section should show percentages
      assert html =~ "%"
    end

    test "selecting a tile shows details", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      open_sidebar(view)

      # Pick a tile that is definitely rendered under the default view
      tile_id = a_visible_tile_id()

      html =
        view
        |> element("[phx-value-id='#{tile_id}']")
        |> render_click()

      assert html =~ "##{tile_id}"
      # Lat/lon position line
      assert html =~ ~r/\d+\.\d°[NS] \d+\.\d°[EW]/
      assert html =~ "Neighbors"
    end

    test "selecting the north-pole pentagon shows the impassable badge", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      open_sidebar(view)

      # Rotate up until the pole (tile 0) is in view
      for _ <- 1..8 do
        view |> element("[phx-value-dir='up']") |> render_click()
      end

      html =
        view
        |> element("[phx-value-id='0']")
        |> render_click()

      assert html =~ "#0"
      assert html =~ "Pentagon (impassable)"
      assert html =~ "Mountains"
      # Pentagons have 5 neighbors
      assert html =~ ">5<"
    end

    test "regenerate changes the seed", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      assert html =~ "12345"

      view |> element("button", "Regenerate") |> render_click()

      html = render(view)
      # Seed should have changed (extremely unlikely to be 12345 again)
      refute html =~ "Seed: 12345"
    end

    test "zoom in increases scale", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      # Default zoom scale
      assert html =~ ">700<"

      view |> element("button", "+") |> render_click()
      html = render(view)
      assert html =~ ">1000<"
    end

    test "zoom out decreases scale", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")

      view |> element("button", "−") |> render_click()
      html = render(view)
      assert html =~ ">500<"
    end

    test "rotating changes the view yaw", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      html = open_sidebar(view)
      assert html =~ "0.0° / 0.0°"

      view |> element("[phx-value-dir='right']") |> render_click()
      html = render(view)
      refute html =~ "0.0° / 0.0°"
    end

    test "rotation wraps around the full globe", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      open_sidebar(view)

      # Default zoom: yaw step = (150/700)/1 ≈ 12.28°. 30 steps > 360°,
      # so yaw must wrap back below 360 rather than growing without bound.
      for _ <- 1..30 do
        view |> element("[phx-value-dir='right']") |> render_click()
      end

      html = render(view)
      assert [_, yaw] = Regex.run(~r/(\d+\.\d)° \/ /, html)
      assert String.to_float(yaw) < 360.0
    end

    test "pitch clamps at the pole", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      open_sidebar(view)

      for _ <- 1..20 do
        view |> element("[phx-value-dir='up']") |> render_click()
      end

      html = render(view)
      # Clamp is 1.50 rad = 85.9°
      assert html =~ "/ 85.9°"
    end

    test "viewport resize rescales the globe", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      # Default 960x700 container: fit scale 350, default factor 2.0 -> 700
      assert html =~ ">700<"

      html =
        view
        |> element("#globe-viewport")
        |> render_hook("viewport_resize", %{w: 1400, h: 1600})

      # fit scale 700 x factor 2.0 -> 1400
      assert html =~ ">1400<"
    end

    test "viewport resize clamps absurd dimensions", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")

      html =
        view
        |> element("#globe-viewport")
        |> render_hook("viewport_resize", %{w: 99_999, h: 1})

      # w clamped to 4000, h to 200 -> fit 100 x 2.0 -> 200
      assert html =~ ">200<"
    end

    test "dragging rotates the globe", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      html = open_sidebar(view)
      assert html =~ "0.0° / 0.0°"

      # Drag left 100px, down 50px at default zoom (scale 700):
      # yaw = 100/700 rad = 8.2°, pitch = 50/700 rad = 4.1°
      html =
        view
        |> element("#globe-viewport")
        |> render_hook("drag_rotate", %{dx: -100, dy: 50})

      assert html =~ "8.2° / 4.1°"
    end

    test "drag pitch clamps at the pole", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      open_sidebar(view)

      html =
        view
        |> element("#globe-viewport")
        |> render_hook("drag_rotate", %{dx: 0, dy: 100_000})

      assert html =~ "/ 85.9°"
    end

    test "keyboard navigation works", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      html = open_sidebar(view)
      assert html =~ "0.0° / 0.0°"

      render_keydown(view, "keydown", %{"key" => "ArrowRight"})
      html = render(view)
      refute html =~ "0.0° / 0.0°"
    end

    test "3D mode pushes a windowed tile payload and toggles back to classic", %{
      conn: conn,
      world: world
    } do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      refute html =~ "globe3d-stage"

      html = view |> element("button", "3D β") |> render_click()
      assert html =~ "globe3d-stage"
      assert html =~ "globe3d-own-#{world.id}"

      # Tiles arrive via push_event as vector data, never through the DOM
      assert_push_event(view, "globe3d:window", %{tiles: tiles, palette: palette})
      refute html =~ "hex-cell3d"

      # Airspace rides along: sparse tile-id => cloud-level map
      assert_push_event(view, "globe3d:airspace", %{levels: levels})
      assert map_size(levels) > 0
      assert Enum.all?(levels, fn {_id, l} -> l in 1..3 end)

      assert length(palette) >= 5 and length(palette) <= 256
      tile_count = BrokenOaths.Worlds.Globe.tile_count(@frequency)
      assert length(tiles) > 0
      assert length(tiles) <= tile_count

      # Each row: [id, palette_index, cx, cy, cz, elevation | corner coords]
      [id, pal, _cx, _cy, _cz, elevation | corners] = hd(tiles)
      assert is_integer(id) and id < tile_count
      assert pal >= 0 and pal < length(palette)
      assert elevation >= 0.0 and elevation <= 1.0
      assert length(corners) in [15, 18]

      # Regenerate pushes a recolored window (seed is in the bucket)
      view |> element("button", "Regenerate") |> render_click()
      assert_push_event(view, "globe3d:window", %{tiles: _})

      # Toggle back restores the classic renderer
      html = view |> element("button", "Classic") |> render_click()
      refute html =~ "globe3d-stage"
      assert html =~ "hex-cell"
      assert html =~ "clip-path:polygon("
    end

    test "3D tile window follows a settled view and shrinks when zoomed in", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      view |> element("button", "3D β") |> render_click()
      assert_push_event(view, "globe3d:window", %{tiles: initial_tiles})
      initial = length(initial_tiles)

      # Deep zoom, settled: window should be much smaller than the mesh
      view
      |> element("#globe3d-stage")
      |> render_hook("view_sync", %{yaw: 0.0, pitch: 0.0, scale: 5000, settled: true})

      assert_push_event(view, "globe3d:window", %{tiles: zoomed_tiles})
      assert length(zoomed_tiles) < initial

      # Rotating to the far side pushes a different window
      view
      |> element("#globe3d-stage")
      |> render_hook("view_sync", %{yaw: 3.14, pitch: 0.0, scale: 5000, settled: true})

      assert_push_event(view, "globe3d:window", %{tiles: far_tiles})
      refute far_tiles == zoomed_tiles

      # Unsettled syncs do not re-window (no DOM churn mid-drag)
      view
      |> element("#globe3d-stage")
      |> render_hook("view_sync", %{yaw: 0.0, pitch: 0.0, scale: 5000, settled: false})

      refute_push_event(view, "globe3d:window", %{tiles: _})
    end

    test "coarse-pointer devices get a budgeted LOD threshold", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=3d")

      html =
        view
        |> element("#globe3d-stage")
        |> render_hook("viewport_resize", %{w: 390, h: 750, coarse: true})

      # f=8 test worlds are under every budget, so k stays at the edge
      # threshold — the attribute contract is what matters here (the
      # full-size math is unit-tested in ProjectionTest)
      assert html =~ ~s(data-lod-k="1.02")
      # And a fresh window was pushed for the new device class
      assert_push_event(view, "globe3d:window", %{tiles: _})
    end

    test "?renderer=css3d keeps the matrix3d facet experiment reachable", %{
      conn: conn,
      world: world
    } do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}?mode=3d&renderer=css3d")
      assert html =~ ~s(data-renderer="css3d")

      assert_push_event(view, "globe3d:window", %{html: window_html})
      assert window_html =~ "hex-cell3d"
      assert window_html =~ "matrix3d("
    end

    test "any tile is reachable and clickable by selector in classic mode", %{
      conn: conn,
      world: world
    } do
      # The far side of the world: aim the camera at it via URL params,
      # then click it through its server-rendered DOM element
      far_tile = BrokenOathsWeb.GlobeHelpers.camera_on(world, 300)
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?#{[{:mode, "classic"} | far_tile]}")
      open_sidebar(view)

      html = BrokenOathsWeb.GlobeHelpers.click_tile(view, 300)
      assert html =~ "#300"
      assert html =~ "Neighbors"
    end

    test "globe mode gameplay flows drive the same server events", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=3d")
      open_sidebar(view)

      # Camera helper = a settled drag; selection helper = a canvas click
      BrokenOathsWeb.GlobeHelpers.look_at(view, world, 300)
      assert_push_event(view, "globe3d:window", %{tiles: _})

      html = BrokenOathsWeb.GlobeHelpers.select_tile_at(view, world, 300)
      assert html =~ "#300"
      # Selection round-trips to the hook for the canvas highlight ring
      assert html =~ ~s(data-selected-id="300")

      # ...as pushed geometry, drawable at ANY zoom (far texture included)
      assert_push_event(view, "globe3d:selected", %{id: 300, center: center, corners: corners})
      assert length(center) == 3
      assert length(corners) in [15, 18]

      # Selecting works identically when fully zoomed out (far mode)
      view
      |> element("#globe3d-stage")
      |> render_hook("view_sync", %{yaw: 0.0, pitch: 0.0, scale: 100, settled: true})

      BrokenOathsWeb.GlobeHelpers.select_tile_at(view, world, 7)
      assert_push_event(view, "globe3d:selected", %{id: 7})

      # Regenerate clears the selection ring
      view |> element("button", "Regenerate") |> render_click()
      assert_push_event(view, "globe3d:selected", %{id: nil})
    end

    test "3D mode has the canvas impostor and texture URL", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      html = view |> element("button", "3D β") |> render_click()

      assert html =~ "globe-canvas"
      assert html =~ "/worlds/#{world.id}/texture.png?seed=#{world.seed}"
      refute html =~ "globe3d-coarse"
    end

    test "impostor clicks select the nearest real tile via select_at", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      open_sidebar(view)
      view |> element("button", "3D β") |> render_click()

      # A point near the north pole selects the pole pentagon
      html =
        view
        |> element("#globe3d-stage")
        |> render_hook("select_at", %{x: 0.01, y: -0.02, z: 0.999})

      assert html =~ "#0"
      assert html =~ "Pentagon (impassable)"
    end

    test "3D mode view_sync updates the sidebar", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      open_sidebar(view)
      view |> element("button", "3D β") |> render_click()

      html =
        view
        |> element("#globe3d-stage")
        |> render_hook("view_sync", %{yaw: 0.5, pitch: -0.25, scale: 1234.6})

      # 0.5 rad = 28.6°, -0.25 rad = -14.3°
      assert html =~ "28.6° / -14.3°"
      assert html =~ "1235px"
    end

    test "the 3D globe is the default view", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}")
      assert html =~ "globe3d-stage"
      assert_push_event(view, "globe3d:window", %{tiles: _})

      # Classic stays reachable by explicit param
      {:ok, _view, html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      refute html =~ "globe3d-stage"
      assert html =~ "hex-cell"
    end

    test "sidebar is collapsed by default and toggles", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      refute html =~ "Terrain Stats"
      refute html =~ "World Info"

      html = open_sidebar(view)
      assert html =~ "Terrain Stats"
      assert html =~ "World Info"

      # The close button inside the sidebar collapses it again
      html = view |> element("button[phx-click='toggle_sidebar']") |> render_click()
      refute html =~ "Terrain Stats"
    end

    test "view params set the initial camera in classic mode", %{conn: conn, world: world} do
      {:ok, view, _html} =
        live(conn, ~p"/worlds/#{world.id}?mode=classic&yaw=90&pitch=20&zoom=1000")

      html = open_sidebar(view)

      assert html =~ "90.0° / 20.0°"
      # zoom=1000 snaps to the exact 1000px zoom level (fit 350 x 2.8571)
      assert html =~ ">1000<"
    end

    test "view params set the initial camera in 3D mode", %{conn: conn, world: world} do
      {:ok, view, html} =
        live(conn, ~p"/worlds/#{world.id}?mode=3d&yaw=45&pitch=-10&zoom=900")

      # The hook reads its starting view from these attributes
      assert html =~ ~s(data-yaw=)
      assert html =~ ~s(data-scale="900")

      html = open_sidebar(view)
      assert html =~ "45.0° / -10.0°"
      assert html =~ "900px"
    end

    test "view params clamp and wrap out-of-range values", %{conn: conn, world: world} do
      {:ok, view, _html} =
        live(conn, ~p"/worlds/#{world.id}?mode=classic&yaw=450&pitch=-89&zoom=999999")

      html = open_sidebar(view)
      # 450° wraps to 90°; -89° clamps to the -85.9° pitch limit
      assert html =~ "90.0° / -85.9°"
    end

    test "malformed view params are ignored", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic&yaw=banana&zoom=")
      html = open_sidebar(view)
      assert html =~ "0.0° / 0.0°"
    end

    test "toggling modes preserves the camera in the URL", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")
      open_sidebar(view)

      # Rotate right once: 150/700 rad = 12.3°
      view |> element("[phx-value-dir='right']") |> render_click()

      html = view |> element("button", "3D β") |> render_click()
      assert html =~ "globe3d-stage"
      assert html =~ "12.3°"

      html = view |> element("button", "Classic") |> render_click()
      refute html =~ "globe3d-stage"
      assert html =~ "12.3°"
    end

    test "name can be updated", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")

      view
      |> form("form[phx-change='update_name']", %{name: "New Name"})
      |> render_change()

      # Verify the world was updated
      updated = BrokenOaths.Worlds.get_world!(world.id)
      assert updated.name == "New Name"
    end

    test "world switcher navigates to different world", %{conn: conn, world: world} do
      other = world_fixture(%{name: "Other World"})
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}?mode=classic")

      view
      |> form("form[phx-change='switch_world']", %{world_id: other.id})
      |> render_change()

      assert_redirect(view, ~p"/worlds/#{other.id}?mode=classic")
    end
  end

  defp open_sidebar(view) do
    view |> element("button[phx-click='toggle_sidebar']") |> render_click()
  end

  # A tile id guaranteed visible under the initial view (yaw 0, pitch 0,
  # default zoom) — derived from the same projection the LiveView uses.
  defp a_visible_tile_id do
    mesh = Globe.get(@frequency)

    view = %{yaw: 0.0, pitch: 0.0, scale: 700, cx: 480, cy: 350, w: 960, h: 700}

    Projection.visible_tiles(mesh, %{}, view)
    |> hd()
    |> Map.fetch!(:id)
  end
end
