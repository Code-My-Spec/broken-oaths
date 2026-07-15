defmodule BrokenOathsSpex.Story879.Criterion7471Spex do
  @moduledoc """
  Story 879 — City Production Queue
  Criterion 7471 — a completed unit spawns on the city tile, or an
  adjacent free land tile if the city tile is occupied.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a finished unit lands beside a occupied city tile" do
    scenario "the city tile is garrisoned when the warrior completes" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city whose own tile is occupied by a garrisoned unit", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        units = Fixtures.player_units(context.world, context.user)
        [settler | _] = for u <- units, u.type == :settler, do: u
        [lord | _] = for u <- units, u.type == :lord, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => city.tile_id})

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [l] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u
          if l.tile_id == city.tile_id do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        {:ok, context |> Map.put(:city, city) |> Map.put(:lord, lord)}
      end

      when_ "a new warrior completes", context do
        for _ <- 1..8, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the warrior spawns on an adjacent free land tile", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        refute warrior.tile_id == context.city.tile_id
        assert warrior.tile_id in Fixtures.adjacent_tiles(context.world, context.city.tile_id)
        assert Fixtures.tile_class(context.world, warrior.tile_id) == :land
        {:ok, context}
      end
    end
  end
end
