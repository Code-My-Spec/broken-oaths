defmodule BrokenOathsSpex.Story953.Criterion2784Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2784 — an unfinished road does not reduce difficult-terrain
  movement cost.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an unfinished road grants no movement discount" do
    scenario "a unit enters difficult terrain whose road is still building" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and selected a unit beside a difficult tile with a building road", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        [unit | _] = Fixtures.player_units(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:unit, unit)}
      end

      when_ "the player moves the unit onto the unfinished road tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.unit.id),
          "to_tile" => "2"
        })

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.unit.id)})

        {:ok, context}
      end

      then_ "the unit pays the full difficult-terrain cost of 2 movement", context do
        assert has_element?(context.play_live, "[data-test='unit-movement']", "0")
        {:ok, context}
      end

      then_ "the road gives no discount until it is complete", context do
        assert has_element?(context.play_live, "[data-test='game-board']")
        {:ok, context}
      end
    end
  end
end
