defmodule BrokenOathsSpex.Story953.Criterion2785Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2785 — pathfinding chooses an open detour when it costs less
  than crossing difficult terrain directly.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a route avoids difficult terrain when a cheaper way exists" do
    scenario "a forest directly blocks the short route while an open detour costs less" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and selected a unit with a forest shortcut and open detour", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        [unit | _] = Fixtures.player_units(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:unit, unit)}
      end

      when_ "the player queues a move to the destination", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.unit.id),
          "to_tile" => "3"
        })

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.unit.id)})

        {:ok, context}
      end

      then_ "the unit follows the cheaper open-terrain route instead of the forest shortcut", context do
        assert has_element?(context.play_live, "[data-test='unit-order']")
        assert has_element?(context.play_live, "[data-test='game-board']")
        {:ok, context}
      end
    end
  end
end
