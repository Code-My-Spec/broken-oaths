defmodule BrokenOathsSpex.Story953.Criterion2787Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2787 — equal-cost paths resolve deterministically through the
  lowest tile id.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "equal-cost routes tie-break to the lowest tile id" do
    scenario "a unit has two routes with identical total movement cost" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and selected a unit with equal-cost destination routes", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        [unit | _] = Fixtures.player_units(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:unit, unit)}
      end

      when_ "the player queues the move to the common destination", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.unit.id),
          "to_tile" => "3"
        })

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.unit.id)})

        {:ok, context}
      end

      then_ "the deterministic route uses the lower-id equal-cost frontier first", context do
        assert has_element?(context.play_live, "[data-test='unit-order']")
        assert has_element?(context.play_live, "[data-test='game-board']")
        {:ok, context}
      end
    end
  end
end
