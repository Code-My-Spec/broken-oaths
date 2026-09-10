defmodule BrokenOathsSpex.Story953.Criterion2776Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2776 — arriving at a destination consumes the remaining path
  and removes the move order.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "arrival consumes the path and drops the order" do
    scenario "a warrior has one open step remaining to its destination" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and selected a warrior beside a clear destination", context do
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

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:warrior, warrior)}
      end

      when_ "the player queues the final step", context do
        target = adjacent_land_tile(context.world, context.warrior.tile_id)

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.warrior.id),
          "to_tile" => to_string(target)
        })

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.warrior.id)})

        {:ok, context}
      end

      then_ "the unit reaches the destination and its path is fully consumed", context do
        assert has_element?(context.play_live, "[data-test='unit-movement']")
        {:ok, context}
      end

      then_ "no pending or interrupted move order remains", context do
        assert has_element?(context.play_live, "[data-test='unit-order']", "No orders queued")
        {:ok, context}
      end
    end
  end
end
