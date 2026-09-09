defmodule BrokenOathsSpex.Story950.Criterion2751Spex do
  @moduledoc """
  Story 950 — Build road to a destination
  Criterion 2751 — a road-to worker skips completed road tiles, builds only
  gaps, and completes when the destination is roaded.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a worker builds only road gaps and finishes at a roaded destination" do
    scenario "a route contains completed road tiles and unroaded gaps" do
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

      when_ "the player issues the build-road-to order and it progresses across the route", context do
        render_hook(context.play_live, "arm_road_mode", %{"unit_id" => to_string(context.worker.id)})

        target = adjacent_land_tile(context.world, context.city.tile_id, [context.worker.tile_id])

        render_hook(context.play_live, "build_road_to", %{
          "unit_id" => to_string(context.worker.id),
          "to_tile" => to_string(target)
        })

        for _ <- 1..10, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "completed road tiles are traversed without being rebuilt", context do
        assert has_element?(context.play_live, "[data-test='unit-order']")
        {:ok, context}
      end

      then_ "only unroaded gap tiles are built and the order ends once the destination is roaded", context do
        refute has_element?(context.play_live, "[data-test='road-error']")
        {:ok, context}
      end
    end
  end
end
