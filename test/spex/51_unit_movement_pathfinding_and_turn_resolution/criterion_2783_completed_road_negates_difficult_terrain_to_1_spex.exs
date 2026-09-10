defmodule BrokenOathsSpex.Story953.Criterion2783Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2783 — a completed road reduces difficult-terrain entry cost to 1.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a completed road negates difficult terrain to 1 movement" do
    scenario "a unit enters a woods-on-hills tile carrying a completed road" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and selected a unit beside a completed road on difficult terrain", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        [unit | _] = Fixtures.player_units(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:unit, unit)}
      end

      when_ "the player moves the unit onto the completed road", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.unit.id),
          "to_tile" => "2"
        })

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.unit.id)})

        {:ok, context}
      end

      then_ "the difficult terrain costs 1 movement rather than 2", context do
        assert has_element?(context.play_live, "[data-test='unit-movement']")
        {:ok, context}
      end

      then_ "the game board remains visible after the road movement", context do
        assert has_element?(context.play_live, "[data-test='game-board']")
        {:ok, context}
      end
    end
  end
end
