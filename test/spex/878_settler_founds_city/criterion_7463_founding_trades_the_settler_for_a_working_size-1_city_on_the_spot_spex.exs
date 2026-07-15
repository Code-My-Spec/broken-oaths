defmodule BrokenOathsSpex.Story878.Criterion7463Spex do
  @moduledoc """
  Story 878 — Settler Founds City
  Criterion 7463 — founding consumes the settler and creates a size-1
  city on that tile, immediately, able to set production right away.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "founding trades the settler for a working size-1 city on the spot" do
    scenario "the settler is consumed and the city is immediately usable" do
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

      given_ "the player has a settler on valid ground", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        {:ok, Map.put(context, :settler, settler)}
      end

      when_ "the player founds a city", context do
        render_hook(context.play_live, "found_city", %{"unit_id" => context.settler.id})
        {:ok, context}
      end

      then_ "the settler is gone immediately, before any turn boundary", context do
        refute Enum.any?(
                 Fixtures.player_units(context.world, context.user),
                 &(&1.id == context.settler.id)
               )

        {:ok, context}
      end

      then_ "a size-1 city stands on the tile", context do
        [city] = Fixtures.player_cities(context.world, context.user)
        assert city.tile_id == context.settler.tile_id
        assert city.size == 1
        {:ok, Map.put(context, :city, city)}
      end

      then_ "the player can open it and set production right away", context do
        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})
        assert has_element?(context.play_live, "[data-test='city-panel']")

        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "warrior"
        })

        assert has_element?(context.play_live, "[data-test='city-production-current']")
        {:ok, context}
      end
    end
  end
end
