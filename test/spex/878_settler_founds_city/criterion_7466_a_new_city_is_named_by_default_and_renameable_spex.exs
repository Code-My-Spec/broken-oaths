defmodule BrokenOathsSpex.Story878.Criterion7466Spex do
  @moduledoc """
  Story 878 — Settler Founds City
  Criterion 7466 — a new city receives a default name its owner can
  rename at any time, and the new name persists.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a new city is named by default and renameable" do
    scenario "renaming a freshly founded city persists" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      given_ "the player just founded a city", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)
        {:ok, Map.put(context, :city, city)}
      end

      when_ "the city panel opens", context do
        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})
        {:ok, context}
      end

      then_ "the city shows a default name", context do
        assert has_element?(context.play_live, "[data-test='city-name']")
        refute has_element?(context.play_live, "[data-test='city-name']", "")
        {:ok, context}
      end

      then_ "the owner can change it to a name of their choosing", context do
        context.play_live
        |> form("[data-test='city-name-form']", city: %{name: "Oakhaven"})
        |> render_submit()

        assert has_element?(context.play_live, "[data-test='city-name']", "Oakhaven")
        {:ok, context}
      end

      then_ "the new name persists after leaving and returning to the world", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        render_hook(play_live, "select_city", %{"city_id" => context.city.id})
        assert has_element?(play_live, "[data-test='city-name']", "Oakhaven")
        {:ok, context}
      end
    end
  end
end
