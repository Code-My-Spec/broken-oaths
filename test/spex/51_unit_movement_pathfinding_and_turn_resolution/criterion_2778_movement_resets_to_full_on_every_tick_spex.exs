defmodule BrokenOathsSpex.Story953.Criterion2778Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2778 — every tick restores a unit's movement to its maximum.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "movement resets to full on every tick" do
    scenario "a warrior has spent all movement during the previous tick" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and spent a warrior's movement", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        :ok = clear_all_camps(context.world)

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        target = adjacent_land_tile(context.world, warrior.tile_id)

        render_hook(play_live, "queue_move", %{
          "unit_id" => to_string(warrior.id),
          "to_tile" => to_string(target)
        })

        render_hook(play_live, "select_unit", %{"unit_id" => to_string(warrior.id)})

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:warrior, warrior)}
      end

      when_ "a tick resolves", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the warrior's movement is restored to its maximum at the top of the tick", context do
        assert has_element?(context.play_live, "[data-test='unit-movement']", "1")
        {:ok, context}
      end
    end
  end
end
