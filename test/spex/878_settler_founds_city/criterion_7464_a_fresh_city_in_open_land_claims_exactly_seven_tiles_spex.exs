defmodule BrokenOathsSpex.Story878.Criterion7464Spex do
  @moduledoc """
  Story 878 — Settler Founds City
  Criterion 7464 — a fresh city claims exactly the city tile plus its
  six adjacent hexes — expansion beyond that comes only from growth.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a fresh city in open land claims exactly seven tiles" do
    scenario "founding with no other city nearby" do
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

      when_ "a settler founds a city with no other city nearby", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.play_live, "found_city", %{"unit_id" => settler.id})
        {:ok, context}
      end

      then_ "its territory is exactly the city tile plus its six adjacent hexes", context do
        [city] = Fixtures.player_cities(context.world, context.user)

        expected =
          MapSet.new([city.tile_id | Fixtures.adjacent_tiles(context.world, city.tile_id)])

        assert MapSet.new(city.territory) == expected
        {:ok, context}
      end

      then_ "no tile beyond that ring is claimed", context do
        [city] = Fixtures.player_cities(context.world, context.user)
        assert length(city.territory) == 7
        {:ok, context}
      end
    end
  end
end
