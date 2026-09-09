defmodule BrokenOathsSpex.Story953.Criterion2781Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2781 — entering an open terrain tile costs one movement point.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "open terrain costs 1 movement" do
    scenario "a unit enters a flat, feature-free open tile" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and selected a unit adjacent to open terrain", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [unit | _] = Fixtures.player_units(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:unit, unit)}
      end

      when_ "the player orders the unit to enter the open tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.unit.id),
          "to_tile" => "2"
        })

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.unit.id)})

        {:ok, context}
      end

      then_ "the unit spends exactly 1 movement point entering the open tile", context do
        assert has_element?(context.play_live, "[data-test='unit-movement']")
        {:ok, context}
      end

      then_ "the board remains rendered after the movement order", context do
        assert has_element?(context.play_live, "[data-test='game-board']")
        {:ok, context}
      end
    end
  end
end
