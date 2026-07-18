defmodule BrokenOathsWeb.WorldLive.NewTest do
  use BrokenOathsTest.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BrokenOaths.Worlds

  describe "New" do
    test "renders the create form with a resource-density picker", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/worlds/new")

      assert html =~ "New Hex World"
      assert has_element?(view, "[data-test='new-world-form']")
      assert has_element?(view, "[data-test='resource-density-slider']")
    end

    test "creates a world with the chosen density and redirects to its show page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/worlds/new")

      {:error, {:live_redirect, %{to: to}}} =
        view
        |> form("[data-test='new-world-form']",
          world: %{"name" => "Dense Lands", "resource_density" => "dense"}
        )
        |> render_submit()

      [id] = Regex.run(~r{/worlds/(\d+)}, to, capture: :all_but_first)
      world = Worlds.get_world!(id)

      assert world.name == "Dense Lands"
      assert world.resource_density == :dense
    end

    test "defaults to standard density when not otherwise chosen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/worlds/new")

      {:error, {:live_redirect, %{to: to}}} =
        view
        |> form("[data-test='new-world-form']", world: %{"name" => "Default Lands"})
        |> render_submit()

      [id] = Regex.run(~r{/worlds/(\d+)}, to, capture: :all_but_first)
      world = Worlds.get_world!(id)

      assert world.resource_density == :standard
    end

    test "a blank name re-renders the form with an error instead of crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/worlds/new")

      html =
        view
        |> form("[data-test='new-world-form']",
          world: %{"name" => "", "resource_density" => "sparse"}
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end
end
