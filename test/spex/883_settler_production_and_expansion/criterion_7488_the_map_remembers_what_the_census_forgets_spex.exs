defmodule BrokenOathsSpex.Story883.Criterion7488Spex do
  @moduledoc """
  Story 883 — Settler Production and Expansion
  Criterion 7488 — losing population to a settler un-works a tile but
  never un-claims territory; once claimed, a city's tiles are
  permanent.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the map remembers what the census forgets" do
    scenario "territory survives a settler's population cost" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a size-2 city that grew once and so claims eight tiles", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [city] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
        territory_before = city.territory

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "settler"})

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:territory_before, territory_before)}
      end

      when_ "it completes a settler and drops to size 1", context do
        for _ <- 1..20, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "it still claims all eight tiles", context do
        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        assert city.size == 1
        assert length(context.territory_before) == 8
        assert MapSet.new(city.territory) == MapSet.new(context.territory_before)
        {:ok, context}
      end

      then_ "only one worked tile remains beyond the free center", context do
        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        assert length(city.worked_tiles) == 1
        {:ok, context}
      end
    end
  end
end
