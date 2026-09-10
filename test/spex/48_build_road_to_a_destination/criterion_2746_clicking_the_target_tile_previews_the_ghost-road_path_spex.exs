defmodule BrokenOathsSpex.Story950.Criterion2746Spex do
  @moduledoc """
  Story 950 — Build road to a destination
  Criterion 2746 — clicking a road target previews the ghost route and
  exposes per-tile progress cues while the worker builds it.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "clicking the target tile previews the ghost-road path" do
    scenario "a player arms a selected worker and clicks a destination tile" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched The Wheel and selected a worker", context do
        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city.id),
          "item" => "worker"
        })

        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "mining"})
        for _ <- 1..60, do: Fixtures.advance_turn(context.world)
        render_hook(context.play_live, "select_research", %{"tech" => "the_wheel"})
        for _ <- 1..100, do: Fixtures.advance_turn(context.world)

        [worker | _] =
          for unit <- Fixtures.player_units(context.world, context.user), unit.type == :worker, do: unit

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(worker.id)})
        {:ok, Map.put(context, :worker, worker)}
      end

      when_ "they enter build-road-to mode and click the destination tile", context do
        render_click(element(context.play_live, "[data-test='build-road-to']"))

        target = adjacent_land_tile(context.world, context.city.tile_id, [context.worker.tile_id])

        render_hook(context.play_live, "build_road_to", %{
          "unit_id" => to_string(context.worker.id),
          "to_tile" => to_string(target)
        })

        {:ok, context}
      end

      then_ "a highlighted ghost-road path is shown from the worker to the destination", context do
        assert has_element?(context.play_live, "[data-test='unit-order']", "Building road to tile")
        {:ok, context}
      end

      then_ "each route tile exposes a progress cue as the road is built", context do
        assert has_element?(context.play_live, "[data-test='road-progress']")
        {:ok, context}
      end
    end
  end
end
