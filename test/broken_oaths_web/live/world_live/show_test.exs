defmodule BrokenOathsWeb.WorldLive.ShowTest do
  use BrokenOathsWeb.ConnCase, async: true

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
      {:ok, _view, html} = live(conn, ~p"/worlds/#{world.id}")
      assert html =~ "Emerald Shores"
      assert html =~ "12345"
      # Should render tile cells with per-tile clip paths
      assert html =~ "hex-cell"
      assert html =~ "clip-path:polygon("
      assert html =~ "globe-disc"
    end

    test "shows world size as tile count", %{conn: conn, world: world} do
      {:ok, _view, html} = live(conn, ~p"/worlds/#{world.id}")
      assert html =~ "GP(#{@frequency})"
      assert html =~ "#{Globe.tile_count(@frequency)} tiles"
    end

    test "shows terrain legend", %{conn: conn, world: world} do
      {:ok, _view, html} = live(conn, ~p"/worlds/#{world.id}")
      assert html =~ "Ocean"
      assert html =~ "Grassland"
      assert html =~ "Mountains"
    end

    test "shows terrain stats", %{conn: conn, world: world} do
      {:ok, _view, html} = live(conn, ~p"/worlds/#{world.id}")
      # Stats section should show percentages
      assert html =~ "%"
    end

    test "selecting a tile shows details", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

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
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

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
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}")
      assert html =~ "12345"

      view |> element("button", "Regenerate") |> render_click()

      html = render(view)
      # Seed should have changed (extremely unlikely to be 12345 again)
      refute html =~ "Seed: 12345"
    end

    test "zoom in increases scale", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}")
      # Default zoom scale
      assert html =~ ">700<"

      view |> element("button", "+") |> render_click()
      html = render(view)
      assert html =~ ">1000<"
    end

    test "zoom out decreases scale", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      view |> element("button", "−") |> render_click()
      html = render(view)
      assert html =~ ">500<"
    end

    test "rotating changes the view yaw", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}")
      assert html =~ "0.0° / 0.0°"

      view |> element("[phx-value-dir='right']") |> render_click()
      html = render(view)
      refute html =~ "0.0° / 0.0°"
    end

    test "rotation wraps around the full globe", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

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
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      for _ <- 1..20 do
        view |> element("[phx-value-dir='up']") |> render_click()
      end

      html = render(view)
      # Clamp is 1.50 rad = 85.9°
      assert html =~ "/ 85.9°"
    end

    test "viewport resize rescales the globe", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}")
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
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      html =
        view
        |> element("#globe-viewport")
        |> render_hook("viewport_resize", %{w: 99_999, h: 1})

      # w clamped to 4000, h to 200 -> fit 100 x 2.0 -> 200
      assert html =~ ">200<"
    end

    test "dragging rotates the globe", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}")
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
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      html =
        view
        |> element("#globe-viewport")
        |> render_hook("drag_rotate", %{dx: 0, dy: 100_000})

      assert html =~ "/ 85.9°"
    end

    test "keyboard navigation works", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}")
      assert html =~ "0.0° / 0.0°"

      render_keydown(view, "keydown", %{"key" => "ArrowRight"})
      html = render(view)
      refute html =~ "0.0° / 0.0°"
    end

    test "name can be updated", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      view
      |> form("form[phx-change='update_name']", %{name: "New Name"})
      |> render_change()

      # Verify the world was updated
      updated = BrokenOaths.Worlds.get_world!(world.id)
      assert updated.name == "New Name"
    end

    test "world switcher navigates to different world", %{conn: conn, world: world} do
      other = world_fixture(%{name: "Other World"})
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      view
      |> form("form[phx-change='switch_world']", %{world_id: other.id})
      |> render_change()

      assert_redirect(view, ~p"/worlds/#{other.id}")
    end
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
