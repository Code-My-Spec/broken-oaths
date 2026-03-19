defmodule BrokenOathsWeb.WorldLive.ShowTest do
  use BrokenOathsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BrokenOaths.WorldsFixtures

  describe "Show" do
    setup do
      %{world: world_fixture(%{name: "Emerald Shores", seed: 12345})}
    end

    test "renders world with hex grid", %{conn: conn, world: world} do
      {:ok, _view, html} = live(conn, ~p"/worlds/#{world.id}")
      assert html =~ "Emerald Shores"
      assert html =~ "12345"
      # Should render hex cells
      assert html =~ "hex-cell"
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

    test "selecting a hex shows details", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      html =
        view
        |> element("[phx-value-q='5'][phx-value-r='5']")
        |> render_click()

      assert html =~ "(5, 5)"
    end

    test "regenerate changes the seed", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}")
      assert html =~ "12345"

      view |> element("button", "Regenerate") |> render_click()

      html = render(view)
      # Seed should have changed (extremely unlikely to be 12345 again)
      refute html =~ "12345"
    end

    test "zoom in increases hex size", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}")
      # Default zoom is index 2 = 8px
      assert html =~ ">8<"

      view |> element("button", "+") |> render_click()
      html = render(view)
      assert html =~ ">12<"
    end

    test "zoom out decreases hex size", %{conn: conn, world: world} do
      {:ok, view, html} = live(conn, ~p"/worlds/#{world.id}")

      view |> element("button", "−") |> render_click()
      html = render(view)
      assert html =~ ">5<"
    end

    test "pan changes viewport coordinates", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      view |> element("[phx-value-dir='right']") |> render_click()
      html = render(view)
      # Viewport should have moved from (0,0)
      assert html =~ "(10, 0)"
    end

    test "keyboard navigation works", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      render_keydown(view, "keydown", %{"key" => "ArrowRight"})
      html = render(view)
      assert html =~ "(10, 0)"
    end

    test "name can be updated", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      view
      |> form("form", %{name: "New Name"})
      |> render_change()

      # Verify the world was updated
      updated = BrokenOaths.Worlds.get_world!(world.id)
      assert updated.name == "New Name"
    end

    test "world switcher navigates to different world", %{conn: conn, world: world} do
      other = world_fixture(%{name: "Other World"})
      {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}")

      view
      |> form("form", %{world_id: other.id})
      |> render_change()

      assert_redirect(view, ~p"/worlds/#{other.id}")
    end
  end
end
