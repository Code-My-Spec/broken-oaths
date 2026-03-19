defmodule BrokenOathsWeb.WorldLive.IndexTest do
  use BrokenOathsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BrokenOaths.WorldsFixtures

  describe "Index" do
    test "renders empty state when no worlds", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/worlds")
      assert html =~ "Hex Worlds"
      assert html =~ "No worlds yet"
    end

    test "lists existing worlds", %{conn: conn} do
      world = world_fixture(%{name: "Test Planet"})
      {:ok, _view, html} = live(conn, ~p"/worlds")
      assert html =~ "Test Planet"
      assert html =~ to_string(world.seed)
    end

    test "creates a new world and redirects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/worlds")

      view |> element("button", "New World") |> render_click()

      # Should redirect to show page
      assert_redirect(view, ~r"/worlds/\d+")
    end

    test "deletes a world", %{conn: conn} do
      world = world_fixture(%{name: "Doomed World"})
      {:ok, view, html} = live(conn, ~p"/worlds")
      assert html =~ "Doomed World"

      view
      |> element("button[phx-value-id='#{world.id}']", "Delete")
      |> render_click()

      refute render(view) =~ "Doomed World"
    end
  end
end
