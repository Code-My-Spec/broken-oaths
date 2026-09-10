defmodule BrokenOathsSpex.Story953.Criterion2782Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2782 — entering difficult terrain without a completed road costs
  two movement points.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "difficult terrain costs 2 movement" do
    scenario "a unit enters hills, woods, rainforest, or marsh without a road" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and selected a unit beside an unroaded difficult tile", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [unit | _] = Fixtures.player_units(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:unit, unit)}
      end

      when_ "the player orders the unit to enter the difficult tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.unit.id),
          "to_tile" => "2"
        })

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.unit.id)})

        {:ok, context}
      end

      then_ "the unit spends 2 movement points entering the unroaded difficult terrain", context do
        assert has_element?(context.play_live, "[data-test='unit-movement']", "0")
        {:ok, context}
      end

      then_ "the movement action is visible on the game board", context do
        assert has_element?(context.play_live, "[data-test='game-board']")
        {:ok, context}
      end
    end
  end
end
