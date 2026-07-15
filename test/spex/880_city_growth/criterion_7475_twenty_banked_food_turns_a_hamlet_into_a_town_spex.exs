defmodule BrokenOathsSpex.Story880.Criterion7475Spex do
  @moduledoc """
  Story 880 — City Growth
  Criterion 7475 — reaching 20 accumulated food grows a size-1 city to
  size 2, visibly in the city panel.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "twenty banked food turns a hamlet into a town" do
    scenario "food accumulates to the size-2 threshold" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a size-1 city whose worked tiles yield food each boundary", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "its accumulated food reaches 20", context do
        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user),
                cc.id == context.city.id,
                do: cc

          if c.food >= 20 or c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "the city becomes size 2", context do
        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        assert city.size == 2
        {:ok, context}
      end

      then_ "the growth is visible in the city panel", context do
        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})
        assert has_element?(context.play_live, "[data-test='city-size']", "2")
        {:ok, context}
      end
    end
  end
end
