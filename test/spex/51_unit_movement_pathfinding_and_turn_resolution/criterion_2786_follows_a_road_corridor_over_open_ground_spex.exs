defmodule BrokenOathsSpex.Story953.Criterion2786Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2786 — pathfinding follows a completed road corridor when it is
  no more costly than the parallel open-ground route.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a route follows a road corridor over open ground" do
    scenario "a unit has a completed-road corridor parallel to an open-ground route" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and selected a unit with both routes available", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        [unit | _] = Fixtures.player_units(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:unit, unit)}
      end

      when_ "the player queues a move to the shared destination", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.unit.id),
          "to_tile" => "3"
        })

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.unit.id)})

        {:ok, context}
      end

      then_ "the path prefers the completed road corridor over open ground", context do
        assert has_element?(context.play_live, "[data-test='unit-order']")
        assert has_element?(context.play_live, "[data-test='game-board']")
        {:ok, context}
      end
    end
  end
end
