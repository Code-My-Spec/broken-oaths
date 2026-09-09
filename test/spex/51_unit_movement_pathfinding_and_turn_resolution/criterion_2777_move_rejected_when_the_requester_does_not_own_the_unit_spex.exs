defmodule BrokenOathsSpex.Story953.Criterion2777Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2777 — a player cannot queue a move for another player's unit.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a move is rejected when the requester does not own the unit" do
    scenario "one player tries to move another player's unit" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "both players have joined the world and the other player owns a unit", context do
        {:ok, other_join_live, _html} = live(context.other_conn, ~p"/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [foreign_unit | _] = Fixtures.player_units(context.world, context.other_user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:foreign_unit, foreign_unit)}
      end

      when_ "the player queues a move for the other player's unit", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.foreign_unit.id),
          "to_tile" => to_string(context.foreign_unit.tile_id)
        })

        {:ok, context}
      end

      then_ "no move order is accepted for the foreign unit", context do
        refute has_element?(context.play_live, "[data-test='unit-order']", "Moving to tile")
        {:ok, context}
      end

      then_ "the requester is told they do not own the unit", context do
        assert has_element?(context.play_live, "[data-test='order-error']", "control")
        {:ok, context}
      end
    end
  end
end
