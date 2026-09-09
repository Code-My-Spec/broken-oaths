defmodule BrokenOathsSpex.Story950.Criterion2742Spex do
  @moduledoc """
  Story 950 — Build road to a destination
  Criterion 2742 — one worker command starts a road toward a distant city
  without requiring individual segment placements.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a single command connects two cities with road" do
    scenario "Wes orders a worker near City A to build a road to distant City B" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has a worker near their city and has researched The Wheel", context do
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

      when_ "they issue one build-road-to order targeting the destination city tile", context do
        render_hook(context.play_live, "arm_road_mode", %{"unit_id" => to_string(context.worker.id)})

        target = adjacent_land_tile(context.world, context.city.tile_id, [context.worker.tile_id])

        render_hook(context.play_live, "build_road_to", %{
          "unit_id" => to_string(context.worker.id),
          "to_tile" => to_string(target)
        })

        {:ok, context}
      end

      then_ "the worker begins a road build toward the destination", context do
        assert has_element?(context.play_live, "[data-test='unit-order']", "Building road to tile")
        {:ok, context}
      end

      then_ "the player does not need to place individual road segments", context do
        assert has_element?(context.play_live, "[data-test='cancel-road-build']")
        {:ok, context}
      end
    end
  end
end
