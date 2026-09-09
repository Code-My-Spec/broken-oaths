defmodule BrokenOathsSpex.Story953.Criterion2774Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2774 — issuing a move spends a unit's remaining movement
  immediately and retains any unfinished path.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "issuing a move spends current movement immediately" do
    scenario "a warrior with two movement receives a three-tile open-path order" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and produced a warrior with a clear destination", context do
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

      when_ "the player queues the three-tile move", context do
        step1 = adjacent_land_tile(context.world, context.warrior.tile_id)
        step2 = adjacent_land_tile(context.world, step1, [context.warrior.tile_id])

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.warrior.id),
          "to_tile" => to_string(step2)
        })

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.warrior.id)})

        {:ok, context}
      end

      then_ "the warrior has immediately spent its available movement advancing along the path", context do
        assert has_element?(context.play_live, "[data-test='unit-movement']", "0")
        {:ok, context}
      end

      then_ "the unfinished final step remains queued for a later turn", context do
        assert has_element?(context.play_live, "[data-test='unit-order']", "Moving to tile")
        {:ok, context}
      end
    end
  end
end
